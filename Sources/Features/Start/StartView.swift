import SwiftUI

struct StartView: View {
    @EnvironmentObject private var routineStore: RoutineStore

    @State private var isShowingCreateRoutine: Bool = false
    @State private var editingRoutine: RoutineWithExercises? = nil
    @State private var routineToDelete: RoutineWithExercises? = nil
    @State private var isShowingPhase3Hint: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Schnellstart")) {
                    Button {
                        isShowingPhase3Hint = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.headline)
                            Text("Leeres Workout starten")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .foregroundColor(.accentColor)
                    }
                }

                Section(
                    header: HStack {
                        Text("Meine Routinen")
                        Spacer()
                        Button {
                            isShowingCreateRoutine = true
                        } label: {
                            Label("Neu", systemImage: "plus")
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                ) {
                    if routineStore.routines.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Noch keine Routinen")
                                .font(.headline)
                            Text("Erstelle deine erste Trainingsvorlage (z. B. Push A oder Ganzkörper).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Erste Routine erstellen") {
                                isShowingCreateRoutine = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(routineStore.routines) { item in
                            RoutineCardRow(
                                item: item,
                                onStart: {
                                    isShowingPhase3Hint = true
                                },
                                onEdit: {
                                    editingRoutine = item
                                },
                                onDelete: {
                                    routineToDelete = item
                                }
                            )
                        }
                        .onMove { source, destination in
                            routineStore.moveRoutines(from: source, to: destination)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Start")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if routineStore.routines.count > 1 {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingCreateRoutine = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Routine")
                }
            }
            .sheet(isPresented: $isShowingCreateRoutine) {
                RoutineEditorView(nextSortOrder: routineStore.routines.count) { routine, exercises in
                    routineStore.saveRoutine(routine, exercises: exercises)
                }
            }
            .sheet(item: $editingRoutine) { item in
                RoutineEditorView(
                    existingRoutine: item,
                    nextSortOrder: routineStore.routines.count
                ) { routine, exercises in
                    routineStore.saveRoutine(routine, exercises: exercises)
                }
            }
            .alert(
                "Routine löschen?",
                isPresented: Binding(
                    get: { routineToDelete != nil },
                    set: { isPresented in
                        if !isPresented { routineToDelete = nil }
                    }
                ),
                presenting: routineToDelete
            ) { item in
                Button("Löschen", role: .destructive) {
                    routineStore.deleteRoutine(id: item.id)
                    routineToDelete = nil
                }
                Button("Abbrechen", role: .cancel) {
                    routineToDelete = nil
                }
            } message: { item in
                Text("Die Routine „\(item.routine.name)“ wird entfernt. Vergangene Workouts bleiben im Verlauf erhalten.")
            }
            .alert("Folgt in Phase 3", isPresented: $isShowingPhase3Hint) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Das aktive Workout-Logging (Sätze, Gewicht, Wiederholungen & Vorher-Werte) kommt im nächsten Schritt in Phase 3.")
            }
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: { routineStore.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { routineStore.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(routineStore.errorMessage ?? "")
            }
        }
    }
}

private struct RoutineCardRow: View {
    let item: RoutineWithExercises
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var exerciseSummary: String {
        if item.exercises.isEmpty {
            return "Noch keine Übungen"
        }
        return item.exercises
            .prefix(4)
            .map { "\($0.routineExercise.targetSets)× \($0.exercise.name)" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.routine.name)
                        .font(.headline)
                    if let notes = item.routine.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }

            Text(exerciseSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(4)

            if item.exercises.count > 4 {
                Text("+\(item.exercises.count - 4) weitere Übungen")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("\(item.exercises.count) Übungen · \(item.totalSets) Sätze")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    onStart()
                } label: {
                    Label("Starten", systemImage: "play.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        let db = AppDatabase.makeInMemory()
        StartView()
            .environmentObject(RoutineStore(database: db))
            .environmentObject(ExerciseStore(database: db))
    }
}
