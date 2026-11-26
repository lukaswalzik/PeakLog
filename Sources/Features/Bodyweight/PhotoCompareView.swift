import SwiftUI
import UIKit

struct PhotoCompareView: View {
    @Environment(\.dismiss) private var dismiss

    let timeline: [PhotoTimelineItem]

    @State private var leftIndex: Int
    @State private var rightIndex: Int

    init(timeline: [PhotoTimelineItem]) {
        // timeline comes newest-first; sort chronologically ascending for intuitive Before -> After
        let sorted = timeline.sorted { $0.recordedAt < $1.recordedAt }
        self.timeline = sorted
        _leftIndex = State(initialValue: 0)
        _rightIndex = State(initialValue: max(0, sorted.count - 1))
    }

    private var leftItem: PhotoTimelineItem? {
        timeline.indices.contains(leftIndex) ? timeline[leftIndex] : nil
    }

    private var rightItem: PhotoTimelineItem? {
        timeline.indices.contains(rightIndex) ? timeline[rightIndex] : nil
    }

    private var comparisonDeltaText: String? {
        guard let left = leftItem, let right = rightItem else { return nil }
        let weightDiff = right.weightKg - left.weightKg
        let sign = weightDiff >= 0 ? "+" : ""
        let days = Calendar.current.dateComponents([.day], from: left.recordedAt, to: right.recordedAt).day ?? 0
        return "\(sign)\(Formatters.weight(weightDiff)) kg · \(abs(days)) Tage"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let delta = comparisonDeltaText {
                    Text(delta)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    compareColumn(title: "Vorher", selection: $leftIndex, item: leftItem)
                    compareColumn(title: "Nachher", selection: $rightIndex, item: rightItem)
                }
                .padding(.horizontal, 12)

                Spacer()
            }
            .padding(.top, 12)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Vorher / Nachher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func compareColumn(
        title: String,
        selection: Binding<Int>,
        item: PhotoTimelineItem?
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if let item = item,
               let image = MediaStorage.shared.loadImage(filename: item.photo.imageFilename, in: .bodyweight) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        VStack {
                            Spacer()
                            HStack {
                                Text("\(Formatters.weight(item.weightKg)) kg")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Spacer()
                                Text(Formatters.shortDate(item.recordedAt))
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 360)
            }

            Picker(title, selection: selection) {
                ForEach(timeline.indices, id: \.self) { idx in
                    Text(timeline[idx].labelText).tag(idx)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }
}
