import SwiftUI

struct CardioPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardioStore: CardioStore

    let existingPlan: CardioPlan?
    let onSave: (CardioPlan) -> Void

    @State private var name: String
    @State private var subtitle: String
    @State private var weeklyGoalSessions: Int
    @State private var progressionNotes: String
    @State private var sessions: [CardioPlanSession]
    @State private var isActive: Bool

    @State private var isShowingAddSession: Bool = false
    @State private var editingSession: CardioPlanSession? = nil

    init(existingPlan: CardioPlan? = nil, onSave: @escaping (CardioPlan) -> Void) {
        self.existingPlan = existingPlan
        self.onSave = onSave
        _name = State(initialValue: existingPlan?.name ?? "")
        _subtitle = State(initialValue: existingPlan?.subtitle ?? "")
        _weeklyGoalSessions = State(initialValue: existingPlan?.weeklyGoalSessions ?? 3)
        _progressionNotes = State(initialValue: existingPlan?.progressionNotes ?? "")
        _sessions = State(initialValue: existingPlan?.sessions.sorted { $0.sortOrder < $1.sortOrder } ?? [])
        _isActive = State(initialValue: existingPlan?.isActive ?? true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan-Details") {
                    TextField("Planname (z. B. Grundfitness & Zone 2)", text: $name)
                    TextField("Kurzbeschreibung (optional)", text: $subtitle)
                    Stepper("Wochenziel: \(weeklyGoalSessions) Einheiten / Woche", value: $weeklyGoalSessions, in: 1...7)
                    Toggle("Als aktiven Cardio-Plan setzen", isOn: $isActive)
                }

                Section {
                    if sessions.isEmpty {
                        VStack(spacing: 8) {
                            Text("Noch keine Einheiten in diesem Plan")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button {
                                isShowingAddSession = true
                            } label: {
                                Label("Erste Einheit hinzufügen", systemImage: "plus.circle.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                editingSession = session
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: session.activityType.systemImage)
                                        .font(.headline)
                                        .foregroundColor(session.activityType.accentColor)
                                        .frame(width: 34, height: 34)
                                        .background(session.activityType.accentColor.opacity(0.14))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        Text("\(session.timing.shortBadge) · \(session.targetDurationMinutes) Min · \(session.targetZone.shortName) (\(session.targetZone.bpmRangeText(maxHR: cardioStore.maxHeartRate)))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if !session.intensityGuide.isEmpty {
                                            Text(session.intensityGuide)
                                                .font(.caption2)
                                                .foregroundColor(.accentColor)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            sessions.remove(atOffsets: offsets)
                        }
                        .onMove { source, destination in
                            sessions.move(fromOffsets: source, toOffset: destination)
                        }

                        Button {
                            isShowingAddSession = true
                        } label: {
                            Label("Einheit hinzufügen", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    HStack {
                        Text("Geplante Einheiten (\(sessions.count))")
                        Spacer()
                        if sessions.count > 1 {
                            EditButton()
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                Section("Steigerung / Notizen (optional)") {
                    TextEditor(text: $progressionNotes)
                        .frame(minHeight: 90)
                        .font(.subheadline)
                }
            }
            .navigationTitle(existingPlan == nil ? "Neuer Cardio-Plan" : "Cardio-Plan bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        savePlan()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingAddSession) {
                CardioPlanSessionEditorView(nextSortOrder: sessions.count) { newSession in
                    sessions.append(newSession)
                }
            }
            .sheet(item: $editingSession) { session in
                CardioPlanSessionEditorView(existingSession: session, nextSortOrder: session.sortOrder) { updated in
                    if let idx = sessions.firstIndex(where: { $0.id == updated.id }) {
                        sessions[idx] = updated
                    }
                }
            }
        }
    }

    private func savePlan() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedSub = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = progressionNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let plan = CardioPlan(
            id: existingPlan?.id ?? UUID().uuidString,
            name: trimmedName,
            subtitle: trimmedSub.isEmpty ? nil : trimmedSub,
            weeklyGoalSessions: weeklyGoalSessions,
            progressionNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            sessions: sessions.enumerated().map { idx, item in
                var copy = item
                copy.sortOrder = idx
                return copy
            },
            isActive: isActive,
            createdAt: existingPlan?.createdAt ?? Date(),
            updatedAt: Date()
        )
        onSave(plan)
        dismiss()
    }
}

struct CardioPlanSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardioStore: CardioStore

    let existingSession: CardioPlanSession?
    let nextSortOrder: Int
    let onSave: (CardioPlanSession) -> Void

    @State private var title: String
    @State private var activityType: CardioActivityType
    @State private var timing: CardioPlanTiming
    @State private var targetDurationMinutes: Int
    @State private var targetZone: HeartRateZone
    @State private var intensityGuide: String
    @State private var notes: String

    private let durationPresets = [15, 20, 25, 30, 35, 45]

    init(
        existingSession: CardioPlanSession? = nil,
        nextSortOrder: Int,
        onSave: @escaping (CardioPlanSession) -> Void
    ) {
        self.existingSession = existingSession
        self.nextSortOrder = nextSortOrder
        self.onSave = onSave
        _title = State(initialValue: existingSession?.title ?? "")
        _activityType = State(initialValue: existingSession?.activityType ?? .walking)
        _timing = State(initialValue: existingSession?.timing ?? .postWorkout)
        _targetDurationMinutes = State(initialValue: existingSession?.targetDurationMinutes ?? 20)
        _targetZone = State(initialValue: existingSession?.targetZone ?? .z2)
        _intensityGuide = State(initialValue: existingSession?.intensityGuide ?? "")
        _notes = State(initialValue: existingSession?.notes ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Einheit") {
                    TextField("Titel (z. B. Post-Workout Incline Walk)", text: $title)

                    Picker("Gerät / Sportart", selection: $activityType) {
                        ForEach(CardioActivityType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }

                    Picker("Wann?", selection: $timing) {
                        ForEach(CardioPlanTiming.allCases) { t in
                            Label(t.displayName, systemImage: t.systemImage).tag(t)
                        }
                    }
                }

                Section("Dauer & Ziel-Puls") {
                    Stepper("Zieldauer: \(targetDurationMinutes) Min", value: $targetDurationMinutes, in: 5...120, step: 5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(durationPresets, id: \.self) { mins in
                                Button {
                                    targetDurationMinutes = mins
                                } label: {
                                    Text("\(mins) Min")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(targetDurationMinutes == mins ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                        .foregroundColor(targetDurationMinutes == mins ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Picker("Ziel-HF-Zone", selection: $targetZone) {
                        ForEach(HeartRateZone.allCases) { zone in
                            Text("\(zone.title) (\(zone.bpmRangeText(maxHR: cardioStore.maxHeartRate)))").tag(zone)
                        }
                    }
                }

                Section("Intensität & Anleitung") {
                    TextField("Vorgabe (z. B. 5,2 km/h · 6 % oder 100 W)", text: $intensityGuide)
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .font(.subheadline)
                }
            }
            .navigationTitle(existingSession == nil ? "Neue Cardio-Einheit" : "Einheit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }
                        let trimmedGuide = intensityGuide.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let result = CardioPlanSession(
                            id: existingSession?.id ?? UUID().uuidString,
                            title: trimmedTitle,
                            activityType: activityType,
                            timing: timing,
                            targetDurationMinutes: targetDurationMinutes,
                            targetZone: targetZone,
                            intensityGuide: trimmedGuide,
                            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                            sortOrder: existingSession?.sortOrder ?? nextSortOrder
                        )
                        onSave(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
