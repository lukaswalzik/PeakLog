import SwiftUI

struct GymsManagementView: View {
    @EnvironmentObject private var gymStore: GymStore

    @State private var isShowingAddSheet: Bool = false
    @State private var editingGym: Gym? = nil
    @State private var gymToDelete: Gym? = nil

    var body: some View {
        List {
            Section(
                header: Text("Meine Gyms"),
                footer: Text("Wenn du ein Gym auswählst, werden deine Workouts diesem Studio zugeordnet und die „Vorher“-Werte im Training bevorzugen automatisch deine letzte Einheit im selben Gym.")
            ) {
                if gymStore.gyms.isEmpty {
                    EmptyStateView(
                        systemImage: "building.2.fill",
                        title: "Noch keine Gyms angelegt",
                        message: "Lege z. B. „Homegym“, „McFIT“ oder „FitX“ an, um Gewichte pro Studio getrennt im Blick zu behalten.",
                        actionTitle: "Erstes Gym anlegen"
                    ) {
                        isShowingAddSheet = true
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(gymStore.gyms) { gym in
                        Button {
                            gymStore.selectedGymId = (gymStore.selectedGymId == gym.id) ? nil : gym.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(gymStore.selectedGymId == gym.id ? .accentColor : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gym.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if let notes = gym.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if gymStore.selectedGymId == gym.id {
                                    Text("Aktiv")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                gymToDelete = gym
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button {
                                editingGym = gym
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Meine Gyms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Neues Gym")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            GymFormView(nextSortOrder: gymStore.gyms.count) { newGym in
                gymStore.save(newGym)
            }
        }
        .sheet(item: $editingGym) { gym in
            GymFormView(existingGym: gym, nextSortOrder: gym.sortOrder) { updated in
                gymStore.save(updated)
            }
        }
        .alert(
            "Gym löschen?",
            isPresented: Binding(
                get: { gymToDelete != nil },
                set: { if !$0 { gymToDelete = nil } }
            ),
            presenting: gymToDelete
        ) { gym in
            Button("Löschen", role: .destructive) {
                gymStore.delete(id: gym.id)
                gymToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                gymToDelete = nil
            }
        } message: { gym in
            Text("Das Gym „\(gym.name)“ wird entfernt. Deine bisherigen Workouts bleiben im Verlauf erhalten.")
        }
    }
}

struct GymFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingGym: Gym?
    let nextSortOrder: Int
    let onSave: (Gym) -> Void

    @State private var name: String
    @State private var notes: String

    init(existingGym: Gym? = nil, nextSortOrder: Int = 0, onSave: @escaping (Gym) -> Void) {
        self.existingGym = existingGym
        self.nextSortOrder = nextSortOrder
        self.onSave = onSave
        _name = State(initialValue: existingGym?.name ?? "")
        _notes = State(initialValue: existingGym?.notes ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Studio-Details")) {
                    TextField("Name (z. B. FitX, Homegym, McFIT)", text: $name)
                    TextField("Notizen (optional, z. B. Technogym-Geräte)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existingGym == nil ? "Neues Gym" : "Gym bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let gym = Gym(
                            id: existingGym?.id ?? UUID().uuidString,
                            name: trimmedName,
                            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                            sortOrder: existingGym?.sortOrder ?? nextSortOrder,
                            createdAt: existingGym?.createdAt ?? Date()
                        )
                        onSave(gym)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
