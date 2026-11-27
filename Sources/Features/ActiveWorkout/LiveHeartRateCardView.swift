import Charts
import SwiftUI

struct LiveHeartRateCardView: View {
    @ObservedObject var receiver: HeartRateReceiver
    let stats: WorkoutHeartRateStats
    let maxHeartRate: Int

    @State private var isPulsing: Bool = false

    private var currentZone: HeartRateZone? {
        guard let bpm = receiver.currentBPM else { return nil }
        return HeartRateZone.zone(for: bpm, maxHR: maxHeartRate)
    }

    private var accentColor: Color {
        currentZone?.color ?? .red
    }

    private var sparklineDomain: ClosedRange<Int> {
        let bpms = stats.recentSamples.map { $0.bpm }
        let minVal = bpms.min() ?? 60
        let maxVal = bpms.max() ?? 140
        let lower = max(30, minVal - 8)
        let upper = min(240, max(lower + 12, maxVal + 8))
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bpm = receiver.currentBPM {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.16))
                            .frame(width: 38, height: 38)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(accentColor)
                            .scaleEffect(isPulsing ? 1.18 : 1.0)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(bpm)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                            Text("bpm")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            if let zone = currentZone {
                                Text(zone.shortName)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(zone.color.opacity(0.18))
                                    .foregroundColor(zone.color)
                                    .clipShape(Capsule())
                            } else {
                                Text("Leicht")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundColor(.secondary)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(currentZone?.title ?? "Live-Herzfrequenz · AirPods Bridge")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let avg = stats.avgBPM, let maxBPM = stats.maxBPM {
                        HStack(spacing: 10) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Ø")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(avg)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Max")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(maxBPM)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                if stats.recentSamples.count >= 3 {
                    Chart(stats.recentSamples) { sample in
                        AreaMark(
                            x: .value("Zeit", sample.recordedAt),
                            yStart: .value("Min", sparklineDomain.lowerBound),
                            yEnd: .value("BPM", sample.bpm)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor.opacity(0.28), accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Zeit", sample.recordedAt),
                            y: .value("BPM", sample.bpm)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(accentColor)
                    }
                    .chartYScale(domain: sparklineDomain)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 38)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: receiver.lastError != nil ? "exclamationmark.triangle.fill" : "heart")
                        .font(.subheadline)
                        .foregroundColor(receiver.lastError != nil ? .orange : .secondary)

                    if let err = receiver.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                        Spacer()
                        Button("Neu starten") {
                            receiver.restart()
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    } else if stats.sampleCount > 0, let avg = stats.avgBPM, let maxBPM = stats.maxBPM {
                        Text("Live-HF wartet")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Ø \(avg) · Max \(maxBPM) bpm")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    } else {
                        Text("Live-HF · wartet auf UDP \(receiver.endpointDisplay)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Circle()
                            .fill(receiver.isListening ? Color.green.opacity(0.75) : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard(padding: 12)
        .onChange(of: receiver.receivedPacketCount) { _ in
            withAnimation(.easeOut(duration: 0.14)) {
                isPulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeIn(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }
}
