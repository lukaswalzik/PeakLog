import PhotosUI
import SwiftUI
import UIKit

struct ExerciseFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingExercise: Exercise?
    let onSave: (Exercise) -> Void

    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    @State private var equipment: Equipment
    @State private var defaultRestSeconds: Int
    @State private var notes: String

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var previewImage: UIImage?
    @State private var imageChanged: Bool = false
    @State private var isShowingCamera: Bool = false

    init(existingExercise: Exercise? = nil, onSave: @escaping (Exercise) -> Void) {
        self.existingExercise = existingExercise
        self.onSave = onSave
        _name = State(initialValue: existingExercise?.name ?? "")
        _muscleGroup = State(initialValue: existingExercise?.muscleGroup ?? .chest)
        _equipment = State(initialValue: existingExercise?.equipment ?? .barbell)
        _defaultRestSeconds = State(initialValue: existingExercise?.defaultRestSeconds ?? 90)
        _notes = State(initialValue: existingExercise?.notes ?? "")
        _previewImage = State(
            initialValue: MediaStorage.shared.loadImage(
                filename: existingExercise?.imageFilename,
                in: .exercises
            )
        )
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Übungsbild")) {
                    VStack(spacing: 12) {
                        if let image = previewImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            ZStack {
                                LinearGradient(
                                    colors: [
                                        muscleGroup.accentColor.opacity(0.22),
                                        muscleGroup.accentColor.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                VStack(spacing: 8) {
                                    Image(systemName: muscleGroup.systemImage)
                                        .font(.system(size: 36, weight: .semibold))
                                        .foregroundColor(muscleGroup.accentColor)
                                    Text("Kein eigenes Foto")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label("Mediathek", systemImage: "photo.on.rectangle.angled")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            if CameraPickerView.isAvailable {
                                Button {
                                    isShowingCamera = true
                                } label: {
                                    Label("Kamera", systemImage: "camera.fill")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if previewImage != nil {
                            Button(role: .destructive) {
                                previewImage = nil
                                imageChanged = true
                            } label: {
                                Label("Bild entfernen", systemImage: "trash")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Allgemein")) {
                    TextField("Übungsname (z. B. Schrägbankdrücken)", text: $name)

                    Picker("Muskelgruppe", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }

                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }

                Section(header: Text("Pausentimer")) {
                    Stepper(
                        value: $defaultRestSeconds,
                        in: 15...300,
                        step: 15
                    ) {
                        HStack {
                            Text("Standard-Pause")
                            Spacer()
                            Text(Formatters.restDuration(defaultRestSeconds))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Notizen (optional)")) {
                    TextField("z. B. Bank auf Stufe 3, Griffbreite schulterbreit", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingExercise == nil ? "Neue Übung" : "Übung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        save()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem = newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            previewImage = uiImage
                            imageChanged = true
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPickerView { captured in
                    previewImage = captured
                    imageChanged = true
                }
                .ignoresSafeArea()
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        var finalImageFilename = existingExercise?.imageFilename
        if imageChanged {
            if let oldFilename = existingExercise?.imageFilename {
                MediaStorage.shared.deleteImage(filename: oldFilename, in: .exercises)
            }
            if let newImage = previewImage {
                finalImageFilename = try? MediaStorage.shared.saveImage(newImage, in: .exercises)
            } else {
                finalImageFilename = nil
            }
        }

        let exercise = Exercise(
            id: existingExercise?.id ?? UUID().uuidString,
            name: trimmedName,
            muscleGroup: muscleGroup,
            equipment: equipment,
            defaultRestSeconds: defaultRestSeconds,
            isCustom: existingExercise?.isCustom ?? true,
            isArchived: existingExercise?.isArchived ?? false,
            notes: normalizedNotes,
            imageFilename: finalImageFilename,
            createdAt: existingExercise?.createdAt ?? Date()
        )
        onSave(exercise)
        dismiss()
    }
}

struct ExerciseFormView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseFormView { _ in }
    }
}
