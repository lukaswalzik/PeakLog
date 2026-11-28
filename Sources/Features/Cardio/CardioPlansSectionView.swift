import SwiftUI

struct CardioPlansSectionView: View {
    @EnvironmentObject private var cardioStore: CardioStore

    let onStartSession: (CardioPlanSession) -> Void
    var compactForStartTab: Bool = false

    @State private var isShowingCreatePlan: Bool = false
    @State private var editingPlan: CardioPlan? = nil
    @State private var planToDelete: CardioPlan? = nil
    @State private var showProgressionGuide: Bool = false
    @State private var expandedSessionId: String? = nil

    private var activePlan: CardioPlan? {
        cardioStore.activePlan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = activePlan {
                planHeaderCard(plan)

                ForEach(plan.sessions.sorted { $0.sortOrder < $1.sortOrder }) { session in
                    sessionCard(session)
                }
            } else {
                emptyPlanCard
            }
        }
        .sheet(isPresented: $isShowingCreatePlan) {
            CardioPlanEditorView { newPlan in
                cardioStore.savePlan(newPlan)
            }
        }
        .sheet(item: $editingPlan) { plan in
            CardioPlanEditorView(existingPlan: plan) { updated in
                cardioStore.savePlan(updated)
            }
        }
        .alert(
            "Cardio-Plan löschen?",
            isPresented: Binding(
                get: { planToDelete != nil },
                set: { if !$0 { planToDelete = nil } }
            ),
            presenting: planToDelete
        ) { plan in
            Button("Löschen", role: .destructive) {
                cardioStore.deletePlan(id: plan.id)
                planToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                planToDelete = nil
            }
        } message: { plan in
            Text("Der Cardio-Plan „\(plan.name)“ wird entfernt. Bereits geloggte Cardio-Einheiten bleiben erhalten.")
        }
    }

    private func planHeaderCard(_ plan: CardioPlan) -> some View {
        let doneThisWeek = cardioStore.sessionsThisWeek.count
        let goal = max(1, plan.weeklyGoalSessions)
        let progress = min(1.0, Double(doneThisWeek) / Double(goal))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk.motion")
                            .font(.caption)
                            .foregroundColor(.teal)
                        Text("CARDIO-PLAN")
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .tracking(0.8)
                            .foregroundColor(.teal)
                    }

                    if cardioStore.plans.count > 1 {
                        Menu {
                            ForEach(cardioStore.plans) { p in
                                Button {
                                    cardioStore.setActivePlan(id: p.id)
                                } label: {
                                    HStack {
                                        Text(p.name)
                                        if p.id == plan.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(plan.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text(plan.name)
                            .font(.headline)
                    }

                    if let sub = plan.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        editingPlan = plan
                    } label: {
                        Label("Plan bearbeiten", systemImage: "pencil")
                    }

                    Button {
                        isShowingCreatePlan = true
                    } label: {
                        Label("Neuen Cardio-Plan erstellen", systemImage: "plus.circle")
                    }

                    Button {
                        cardioStore.duplicatePlan(plan)
                    } label: {
                        Label("Plan duplizieren", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button {
                        cardioStore.restoreDefaultStarterPlan()
                    } label: {
                        Label("Starter-Plan wiederherstellen", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        planToDelete = plan
                    } label: {
                        Label("Plan löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            // Weekly progress bar
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Diese Woche: \(doneThisWeek) / \(goal) Einheiten")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(doneThisWeek >= goal ? .green : .primary)
                    Spacer()
                    Text("\(cardioStore.minutesThisWeek) Min geloggt · Zone 2: \(HeartRateZone.z2.bpmRangeText(maxHR: cardioStore.maxHeartRate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(doneThisWeek >= goal ? .green : .teal)
            }

            if let guide = plan.progressionNotes, !guide.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showProgressionGuide.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption2)
                            .foregroundColor(.teal)
                        Text(showProgressionGuide ? "Steigerungs-Leitfaden ausblenden" : "Steigerungs-Leitfaden anzeigen (Woche 1–5+)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.teal)
                        Spacer()
                        Image(systemName: showProgressionGuide ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.teal)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.teal.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                if showProgressionGuide {
                    Text(guide)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .strongCard()
    }

    private func sessionCard(_ session: CardioPlanSession) -> some View {
        let completedThisWeek = cardioStore.hasCompletedPlannedSessionThisWeek(session)
        let isExpanded = expandedSessionId == session.id

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: session.activityType.systemImage)
                        .font(.headline)
                        .foregroundColor(session.activityType.accentColor)
                        .frame(width: 40, height: 40)
                        .background(session.activityType.accentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if completedThisWeek {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Label(session.timing.shortBadge, systemImage: session.timing.systemImage)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(session.timing.color.opacity(0.14))
                            .foregroundColor(session.timing.color)
                            .clipShape(Capsule())

                        Text("\(session.targetDurationMinutes) Min")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.secondary)

                        Text("\(session.targetZone.shortName) · \(session.targetZone.bpmRangeText(maxHR: cardioStore.maxHeartRate))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(session.targetZone.color.opacity(0.16))
                            .foregroundColor(session.targetZone.color)
                            .clipShape(Capsule())
                    }
                }

                Spacer(minLength: 4)

                Button {
                    onStartSession(session)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.targetZone.color == .yellow ? .orange : session.activityType.accentColor)
                .controlSize(.small)
            }

            if !session.intensityGuide.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.medium")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text(session.intensityGuide)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    if let notes = session.notes, !notes.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedSessionId = isExpanded ? nil : session.id
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let notes = session.notes, !notes.isEmpty, (!compactForStartTab || isExpanded) {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .strongCard(padding: 12)
    }

    private var emptyPlanCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 30))
                .foregroundColor(.teal)
            Text("Kein Cardio-Plan aktiv")
                .font(.headline)
            Text("Erstelle deinen eigenen Cardio-Trainingsplan oder lade den Grundfitness-Starter-Plan.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Starter-Plan laden") {
                    cardioStore.restoreDefaultStarterPlan()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Neuer Plan") {
                    isShowingCreatePlan = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .strongCard()
    }
}
