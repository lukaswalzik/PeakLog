import Charts
import PhotosUI
import SwiftUI
import UIKit

struct ExerciseDetailView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var historyStore: HistoryStore

    let exercise: Exercise

    @State private var stats: ExerciseStats = .empty
    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingCamera: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var fullscreenImage: UIImage? = nil

    private var currentExercise: Exercise {
        exerciseStore.exercises.first(where: { $0.id == exercise.id }) ?? exercise
    }

    private var exerciseImage: UIImage? {
        MediaStorage.shared.loadImage(filename: currentExercise.imageFilename, in: .exercises)
    }

    private var chartPoints: [ExerciseProgressPoint] {
        stats.history.filter { $0.bestEstimated1RM > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroImageCard
                infoCard
                prCards
                chartCard
                historySection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(currentExercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Bearbeiten") {
                    isShowingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            ExerciseFormView(existingExercise: currentExercise) { updated in
                exerciseStore.save(updated)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPickerView { captured in
                saveNewPhoto(captured)
            }
            .ignoresSafeArea()
        }
        .sheet(
            isPresented: Binding(
                get: { fullscreenImage != nil },
                set: { if !$0 { fullscreenImage = nil } }
            )
        ) {
            if let img = fullscreenImage {
                FullscreenImageView(image: img, caption: currentExercise.name)
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        saveNewPhoto(uiImage)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .onAppear {
            stats = historyStore.fetchStats(forExerciseId: exercise.id)
        }
        .onChange(of: historyStore.completedWorkouts.count) { _ in
            stats = historyStore.fetchStats(forExerciseId: exercise.id)
        }
    }

    private var heroImageCard: some View {
        VStack(spacing: 10) {
            if let image = exerciseImage {
                Button {
                    fullscreenImage = image
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                            .padding(10)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            currentExercise.muscleGroup.accentColor.opacity(0.24),
                            currentExercise.muscleGroup.accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: 8) {
                        Image(systemName: currentExercise.muscleGroup.systemImage)
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(currentExercise.muscleGroup.accentColor)
                        Text("Füge ein Foto hinzu (z. B. Gerät oder Ausführung)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(exerciseImage == nil ? "Foto wählen" : "Foto ändern", systemImage: "photo.on.rectangle.angled")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if CameraPickerView.isAvailable {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Kamera", systemImage: "camera.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .strongCard(padding: 12)
    }

    private func saveNewPhoto(_ image: UIImage) {
        let oldFilename = currentExercise.imageFilename
        if let newFilename = try? MediaStorage.shared.saveImage(image, in: .exercises) {
            var updated = currentExercise
            updated.imageFilename = newFilename
            exerciseStore.save(updated)
            if let old = oldFilename {
                MediaStorage.shared.deleteImage(filename: old, in: .exercises)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(currentExercise.muscleGroup.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(currentExercise.muscleGroup.accentColor.opacity(0.15))
                    .foregroundColor(currentExercise.muscleGroup.accentColor)
                    .clipShape(Capsule())

                Text(currentExercise.equipment.displayName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())

                Spacer()

                Label(Formatters.restDuration(currentExercise.defaultRestSeconds), systemImage: "timer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = currentExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var prCards: some View {
        HStack(spacing: 10) {
            PRCard(
                title: "Bestes 1RM",
                value: stats.bestEstimated1RM.map { "\(Formatters.weight($0)) kg" } ?? "–",
                accent: currentExercise.muscleGroup.accentColor
            )
            PRCard(
                title: "Max. Gewicht",
                value: stats.bestWeightKg.map { "\(Formatters.weight($0)) kg" } ?? "–",
                accent: .primary
            )
            PRCard(
                title: "Bestes Satz-Vol.",
                value: stats.bestSetVolumeKg.map { "\(Formatters.weight($0)) kg" } ?? "–",
                accent: .primary
            )
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Geschätztes 1RM (Epley)")
                .font(.headline)

            if chartPoints.isEmpty {
                Text("Schließe mindestens einen Arbeitssatz mit Gewicht und Wiederholungen ab, um den Fortschritt im Diagramm zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                Chart(chartPoints) { point in
                    AreaMark(
                        x: .value("Datum", point.date),
                        y: .value("1RM (kg)", point.bestEstimated1RM)
                    )
                    .foregroundStyle(currentExercise.muscleGroup.accentColor.opacity(0.18))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("1RM (kg)", point.bestEstimated1RM)
                    )
                    .foregroundStyle(currentExercise.muscleGroup.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("1RM (kg)", point.bestEstimated1RM)
                    )
                    .foregroundStyle(currentExercise.muscleGroup.accentColor)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verlauf (\(stats.history.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            if stats.history.isEmpty {
                Text("Diese Übung wurde noch in keinem abgeschlossenen Workout geloggt.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
            } else {
                ForEach(stats.history.reversed()) { point in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(point.workoutName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(Formatters.shortDate(point.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(point.sets) { workoutSet in
                            HStack {
                                Text(workoutSet.setType.shortBadge ?? "\(workoutSet.setOrder)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(workoutSet.setType == .warmup ? .orange : .primary)
                                    .frame(width: 22, height: 22)
                                    .background(Color(uiColor: .tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))

                                if let w = workoutSet.weightKg, let r = workoutSet.reps {
                                    Text("\(Formatters.weight(w)) kg × \(r)")
                                        .font(.subheadline)
                                } else if let r = workoutSet.reps {
                                    Text("\(r) Wdh.")
                                        .font(.subheadline)
                                } else {
                                    Text("Abgeschlossen")
                                        .font(.subheadline)
                                }

                                Spacer()

                                if workoutSet.setType != .warmup,
                                   let w = workoutSet.weightKg,
                                   let r = workoutSet.reps,
                                   w > 0, r > 0 {
                                    Text("1RM ~\(Formatters.weight(OneRepMaxCalculator.estimatedOneRepMax(weightKg: w, reps: r))) kg")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strongCard()
                }
            }
        }
    }
}

private struct PRCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard(padding: 12)
    }
}
