import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutBannerView(context: context)
                .activityBackgroundTint(Color(red: 0.07, green: 0.09, blue: 0.16).opacity(0.92))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLinkURL(for: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: context.state.activityIconName)
                                .font(.caption2)
                                .foregroundColor(context.state.isCardio ? .green : .cyan)
                            Text(context.state.workoutName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(context.state.isPaused ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                            if context.state.isPaused {
                                Text("Pausiert")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            } else {
                                Text(context.state.effectiveTimerStartDate, style: .timer)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        if let bpm = context.state.heartRateBPM {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundColor(zoneColor(for: context.state.heartRateZoneShort))
                                Text("\(bpm)")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                Text("bpm")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            if let zone = context.state.heartRateZoneShort {
                                Text(zone)
                                    .font(.caption2)
                                    .fontWeight(.heavy)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(zoneColor(for: zone).opacity(0.28))
                                    .foregroundColor(zoneColor(for: zone))
                                    .clipShape(Capsule())
                            }
                        } else if context.state.isCardio {
                            if let zone = context.state.heartRateZoneShort {
                                Text(zone)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(zoneColor(for: zone))
                                Text("Zone")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else {
                            Text("\(context.state.completedSets)/\(context.state.totalSets)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.cyan)
                            Text("Sätze")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isCardio {
                        cardioExpandedBottom(context: context)
                    } else {
                        strengthExpandedBottom(context: context)
                    }
                }
            } compactLeading: {
                if context.state.isCardio {
                    HStack(spacing: 4) {
                        Image(systemName: context.state.activityIconName)
                            .font(.caption2)
                            .foregroundColor(context.state.isPaused ? .orange : .green)
                        if context.state.isPaused {
                            Text("Pause")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        } else {
                            Text(context.state.effectiveTimerStartDate, style: .timer)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .frame(maxWidth: 44, alignment: .leading)
                        }
                    }
                } else if let restInterval = context.state.activeRestInterval {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                        Text(timerInterval: restInterval, countsDown: true)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.cyan)
                            .frame(maxWidth: 42, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "dumbbell.fill")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                        Text("\(context.state.completedSets)/\(context.state.totalSets)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
            } compactTrailing: {
                if let bpm = context.state.heartRateBPM {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(zoneColor(for: context.state.heartRateZoneShort))
                        Text("\(bpm)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(zoneColor(for: context.state.heartRateZoneShort))
                    }
                } else if context.state.isCardio {
                    Text(context.state.heartRateZoneShort ?? "Z2")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .foregroundColor(zoneColor(for: context.state.heartRateZoneShort))
                } else {
                    Text(context.state.effectiveTimerStartDate, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.green)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 44, alignment: .trailing)
                }
            } minimal: {
                if let bpm = context.state.heartRateBPM {
                    Text("\(bpm)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(zoneColor(for: context.state.heartRateZoneShort))
                } else if let restInterval = context.state.activeRestInterval {
                    ProgressView(timerInterval: restInterval, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: "timer")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                    .progressViewStyle(.circular)
                    .tint(.cyan)
                } else {
                    Image(systemName: context.state.activityIconName)
                        .font(.caption2)
                        .foregroundColor(context.state.isCardio ? .green : .cyan)
                }
            }
            .keylineTint(
                context.state.activeRestInterval != nil
                    ? .cyan
                    : (context.state.heartRateBPM != nil
                        ? zoneColor(for: context.state.heartRateZoneShort)
                        : (context.state.isCardio ? .green : .blue))
            )
            .widgetURL(deepLinkURL(for: context.state))
        }
    }

    @ViewBuilder
    private func cardioExpandedBottom(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let targetMins = context.state.targetDurationMinutes, targetMins > 0, !context.state.isPaused {
                let targetEnd = context.state.effectiveTimerStartDate.addingTimeInterval(TimeInterval(targetMins * 60))
                if targetEnd > context.state.effectiveTimerStartDate {
                    HStack(spacing: 8) {
                        Text("Ziel \(targetMins) Min")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.8))

                        ProgressView(timerInterval: context.state.effectiveTimerStartDate...targetEnd, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(zoneColor(for: context.state.targetZoneShort ?? context.state.heartRateZoneShort))
                    }
                }
            }

            HStack(spacing: 8) {
                if let subtitle = context.state.currentExerciseName, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                } else {
                    Text("Cardio aktiv")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer(minLength: 4)

                if let guidance = context.state.targetZoneGuidance {
                    Text(guidance)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(guidanceColor(guidance).opacity(0.24))
                        .foregroundColor(guidanceColor(guidance))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func strengthExpandedBottom(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let restInterval = context.state.activeRestInterval {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Text("Pause")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))

                    ProgressView(timerInterval: restInterval, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.cyan)

                    Text(timerInterval: restInterval, countsDown: true)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.cyan)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                if let exercise = context.state.currentExerciseName, !exercise.isEmpty {
                    Text(exercise)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text("Training aktiv")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer(minLength: 4)

                Text("\(context.state.completedSets)/\(context.state.totalSets) Sätze · \(formattedVolume(context.state.totalVolumeKg))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func deepLinkURL(for state: WorkoutActivityAttributes.ContentState) -> URL? {
        URL(string: state.isCardio ? "strongtracker://active-cardio" : "strongtracker://active-workout")
    }

    private func zoneColor(for shortName: String?) -> Color {
        switch shortName {
        case "Z1": return .cyan
        case "Z2": return .green
        case "Z3": return .yellow
        case "Z4": return .orange
        case "Z5": return .red
        default: return .red
        }
    }

    private func guidanceColor(_ guidance: String) -> Color {
        if guidance.contains("Zielbereich") { return .green }
        if guidance.contains("zügiger") { return .cyan }
        return .orange
    }

    private func formattedVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1f t", kg / 1000.0)
        }
        return "\(Int(kg.rounded())) kg"
    }
}

private struct LockScreenWorkoutBannerView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    private var setProgress: Double {
        guard context.state.totalSets > 0 else { return 0 }
        return min(1.0, Double(context.state.completedSets) / Double(context.state.totalSets))
    }

    private var hrColor: Color {
        switch context.state.heartRateZoneShort {
        case "Z1": return .cyan
        case "Z2": return .green
        case "Z3": return .yellow
        case "Z4": return .orange
        case "Z5": return .red
        default: return .red
        }
    }

    private var formattedVolume: String {
        let kg = context.state.totalVolumeKg
        if kg >= 1000 {
            return String(format: "%.1f t", kg / 1000.0)
        }
        return "\(Int(kg.rounded())) kg"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: context.state.isCardio
                                    ? [Color(red: 0.05, green: 0.58, blue: 0.48), Color(red: 0.08, green: 0.40, blue: 0.65)]
                                    : [Color(red: 0.11, green: 0.36, blue: 0.92), Color(red: 0.28, green: 0.20, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: context.state.activityIconName)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.workoutName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let exercise = context.state.currentExerciseName, !exercise.isEmpty {
                        Text(exercise)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text(context.state.isCardio ? "PeakLog · Live Cardio" : "PeakLog · Aktives Training")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    if let bpm = context.state.heartRateBPM {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                            Text("\(bpm)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                            if let zone = context.state.heartRateZoneShort {
                                Text(zone)
                                    .font(.caption2)
                                    .fontWeight(.heavy)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(hrColor.opacity(0.24))
                        .foregroundColor(hrColor)
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.isPaused ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        if context.state.isPaused {
                            Text("Pausiert")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        } else {
                            Text(context.state.effectiveTimerStartDate, style: .timer)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            if context.state.isCardio {
                VStack(spacing: 5) {
                    HStack {
                        if let guidance = context.state.targetZoneGuidance {
                            Text(guidance)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(guidance.contains("Zielbereich") ? .green : (guidance.contains("zügiger") ? .cyan : .orange))
                        } else if let targetZone = context.state.targetZoneShort {
                            Text("Zielzone \(targetZone)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Text("Live Cardio läuft")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        if let targetMins = context.state.targetDurationMinutes {
                            Text("Ziel: \(targetMins) Min")
                                .font(.caption)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.cyan)
                        }
                    }

                    if let targetMins = context.state.targetDurationMinutes, targetMins > 0, !context.state.isPaused {
                        let targetEnd = context.state.effectiveTimerStartDate.addingTimeInterval(TimeInterval(targetMins * 60))
                        if targetEnd > context.state.effectiveTimerStartDate {
                            ProgressView(timerInterval: context.state.effectiveTimerStartDate...targetEnd, countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .progressViewStyle(.linear)
                            .tint(hrColor)
                        }
                    }
                }
            } else if let restInterval = context.state.activeRestInterval {
                HStack(spacing: 8) {
                    Label("Pause", systemImage: "timer")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)

                    ProgressView(timerInterval: restInterval, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.cyan)

                    Text(timerInterval: restInterval, countsDown: true)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.cyan)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.cyan.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 5) {
                    HStack {
                        Text("\(context.state.completedSets)/\(context.state.totalSets) Sätze abgeschlossen")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.82))
                        Spacer()
                        Text(formattedVolume)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.cyan)
                    }

                    ProgressView(value: setProgress)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
