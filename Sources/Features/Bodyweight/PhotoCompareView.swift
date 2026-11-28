import SwiftUI
import UIKit

struct PhotoCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var wellnessStore: WellnessStore
    @EnvironmentObject private var nutritionStore: NutritionStore

    enum CompareMode: String, CaseIterable, Identifiable {
        case slider = "Wisch-Slider"
        case sideBySide = "Nebeneinander"

        var id: String { rawValue }
    }

    enum PickingSlot: String, CaseIterable, Identifiable {
        case before = "Vorher wählen"
        case after = "Nachher wählen"

        var id: String { rawValue }
    }

    let timeline: [PhotoTimelineItem]

    @State private var mode: CompareMode = .slider
    @State private var pickingSlot: PickingSlot = .before
    @State private var leftIndex: Int
    @State private var rightIndex: Int
    @State private var sliderFraction: CGFloat = 0.5
    @State private var lastCrossedHalf: Bool = false
    @State private var renderedShareImage: UIImage? = nil

    init(timeline: [PhotoTimelineItem]) {
        // Sort chronologically ascending for intuitive Before -> After
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

    private var leftImage: UIImage? {
        guard let item = leftItem else { return nil }
        return MediaStorage.shared.loadImage(filename: item.photo.imageFilename, in: .bodyweight)
    }

    private var rightImage: UIImage? {
        guard let item = rightItem else { return nil }
        return MediaStorage.shared.loadImage(filename: item.photo.imageFilename, in: .bodyweight)
    }

    private var weightDiffKg: Double? {
        guard let left = leftItem, let right = rightItem else { return nil }
        return right.weightKg - left.weightKg
    }

    private var daysDiff: Int? {
        guard let left = leftItem, let right = rightItem else { return nil }
        return Calendar.current.dateComponents([.day], from: left.recordedAt, to: right.recordedAt).day
    }

    private var leftBodyFatPercent: Double? {
        guard let left = leftItem else { return nil }
        return estimateBodyFat(near: left.recordedAt)
    }

    private var rightBodyFatPercent: Double? {
        guard let right = rightItem else { return nil }
        return estimateBodyFat(near: right.recordedAt)
    }

    private var bodyFatDiffPercent: Double? {
        guard let l = leftBodyFatPercent, let r = rightBodyFatPercent else { return nil }
        return r - l
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Ansicht", selection: $mode) {
                        ForEach(CompareMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    deltaBadgesRow
                        .padding(.horizontal, 16)

                    if mode == .slider {
                        sliderComparisonView
                            .padding(.horizontal, 16)
                    } else {
                        sideBySideComparisonView
                            .padding(.horizontal, 14)
                    }

                    thumbnailSelectorCard
                        .padding(.horizontal, 16)

                    if let shareImg = renderedShareImage {
                        ShareLink(
                            item: Image(uiImage: shareImg),
                            preview: SharePreview("PeakLog Vorher / Nachher", image: Image(uiImage: shareImg))
                        ) {
                            Label("Vergleich als Bild teilen", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Vorher / Nachher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let shareImg = renderedShareImage {
                        ShareLink(
                            item: Image(uiImage: shareImg),
                            preview: SharePreview("PeakLog Vorher / Nachher", image: Image(uiImage: shareImg))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                renderShareCard()
            }
            .onChange(of: leftIndex) { _ in
                renderShareCard()
            }
            .onChange(of: rightIndex) { _ in
                renderShareCard()
            }
        }
    }

    // MARK: - Delta Summary Pills

    private var deltaBadgesRow: some View {
        HStack(spacing: 8) {
            if let diff = weightDiffKg {
                let sign = diff >= 0 ? "+" : ""
                let color: Color = abs(diff) < 0.1 ? .secondary : (diff < 0 ? .green : .orange)
                deltaPill(
                    icon: "scalemass.fill",
                    text: "\(sign)\(Formatters.weight(diff)) kg",
                    color: color
                )
            }

            if let days = daysDiff {
                let absDays = abs(days)
                let label: String = absDays >= 14
                    ? "\(absDays) Tage (\(absDays / 7) Wo.)"
                    : "\(absDays) Tage"
                deltaPill(
                    icon: "calendar",
                    text: label,
                    color: .accentColor
                )
            }

            if let bfDiff = bodyFatDiffPercent {
                let sign = bfDiff >= 0 ? "+" : ""
                let formatted = String(format: "%@%.1f %% KFA", sign, bfDiff).replacingOccurrences(of: ".", with: ",")
                let color: Color = abs(bfDiff) < 0.2 ? .secondary : (bfDiff < 0 ? .green : .orange)
                deltaPill(
                    icon: "figure.arms.open",
                    text: formatted,
                    color: color
                )
            }
        }
    }

    private func deltaPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    // MARK: - Interactive Wipe Slider Mode

    private var sliderComparisonView: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let splitX = width * sliderFraction

                ZStack {
                    // Base layer: AFTER photo (right side)
                    if let afterImg = rightImage {
                        Image(uiImage: afterImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()
                    } else {
                        Color(uiColor: .secondarySystemGroupedBackground)
                    }

                    // Masked overlay layer: BEFORE photo (left side up to splitX)
                    if let beforeImg = leftImage {
                        Image(uiImage: beforeImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()
                            .mask(
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .frame(width: max(0, splitX))
                                    Spacer(minLength: 0)
                                }
                            )
                    }

                    // Top floating badges
                    VStack {
                        HStack {
                            if let left = leftItem {
                                overlayTag(
                                    title: "VORHER",
                                    weight: "\(Formatters.weight(left.weightKg)) kg",
                                    date: Formatters.shortDate(left.recordedAt),
                                    bf: leftBodyFatPercent,
                                    accent: .blue
                                )
                            }
                            Spacer()
                            if let right = rightItem {
                                overlayTag(
                                    title: "NACHHER",
                                    weight: "\(Formatters.weight(right.weightKg)) kg",
                                    date: Formatters.shortDate(right.recordedAt),
                                    bf: rightBodyFatPercent,
                                    accent: .green
                                )
                            }
                        }
                        .padding(10)

                        Spacer()

                        Text("← Ziehen zum Vergleichen →")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.48))
                            .clipShape(Capsule())
                            .padding(.bottom, 10)
                    }

                    // Vertical divider line + circular drag handle
                    ZStack {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2.5, height: height)
                            .shadow(color: .black.opacity(0.45), radius: 3)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                            .overlay(
                                Image(systemName: "chevron.left.chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    }
                    .position(x: splitX, y: height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = value.location.x / max(1, width)
                            let clamped = min(0.95, max(0.05, raw))
                            let isNearCenter = abs(clamped - 0.5) < 0.015
                            if isNearCenter && !lastCrossedHalf {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                lastCrossedHalf = true
                            } else if !isNearCenter {
                                lastCrossedHalf = false
                            }
                            sliderFraction = clamped
                        }
                )
            }
            .frame(height: 410)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func overlayTag(title: String, weight: String, date: String, bf: Double?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
            }
            Text(weight)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
            HStack(spacing: 4) {
                Text(date)
                    .font(.system(size: 10))
                    .opacity(0.85)
                if let bf = bf {
                    Text("· \(String(format: "%.1f%%", bf).replacingOccurrences(of: ".", with: ","))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan)
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Side-by-Side Mode

    private var sideBySideComparisonView: some View {
        HStack(spacing: 10) {
            compareColumn(title: "VORHER", accent: .blue, item: leftItem, image: leftImage, bf: leftBodyFatPercent)
            compareColumn(title: "NACHHER", accent: .green, item: rightItem, image: rightImage, bf: rightBodyFatPercent)
        }
    }

    private func compareColumn(
        title: String,
        accent: Color,
        item: PhotoTimelineItem?,
        image: UIImage?,
        bf: Double?
    ) -> some View {
        VStack(spacing: 6) {
            if let item = item, let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        VStack {
                            HStack {
                                Text(title)
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.6)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(accent.opacity(0.85))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(8)

                            Spacer()

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(Formatters.weight(item.weightKg)) kg")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                    Spacer()
                                    Text(Formatters.shortDate(item.recordedAt))
                                        .font(.caption2)
                                }
                                if let bf = bf {
                                    Text("KFA ~\(String(format: "%.1f %%", bf).replacingOccurrences(of: ".", with: ","))")
                                        .font(.caption2)
                                        .foregroundColor(.cyan)
                                }
                                if let cap = item.photo.caption, !cap.isEmpty {
                                    Text(cap)
                                        .font(.caption2)
                                        .opacity(0.85)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.62))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 360)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Thumbnail Filmstrip Selector

    private var thumbnailSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("Slot", selection: $pickingSlot) {
                    ForEach(PickingSlot.allCases) { slot in
                        Text(slot.rawValue).tag(slot)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let tmp = leftIndex
                    leftIndex = rightIndex
                    rightIndex = tmp
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Vorher und Nachher tauschen")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timeline.indices, id: \.self) { idx in
                        let item = timeline[idx]
                        let isBefore = idx == leftIndex
                        let isAfter = idx == rightIndex

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if pickingSlot == .before {
                                leftIndex = idx
                            } else {
                                rightIndex = idx
                            }
                        } label: {
                            ZStack(alignment: .topLeading) {
                                if let thumb = MediaStorage.shared.loadImage(filename: item.photo.imageFilename, in: .bodyweight) {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 66, height: 88)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemFill))
                                        .frame(width: 66, height: 88)
                                }

                                VStack {
                                    HStack(spacing: 3) {
                                        if isBefore {
                                            Text("V")
                                                .font(.system(size: 9, weight: .heavy))
                                                .foregroundColor(.white)
                                                .frame(width: 16, height: 16)
                                                .background(Color.blue)
                                                .clipShape(Circle())
                                        }
                                        if isAfter {
                                            Text("N")
                                                .font(.system(size: 9, weight: .heavy))
                                                .foregroundColor(.white)
                                                .frame(width: 16, height: 16)
                                                .background(Color.green)
                                                .clipShape(Circle())
                                        }
                                        Spacer()
                                    }
                                    .padding(4)

                                    Spacer()

                                    VStack(spacing: 0) {
                                        Text("\(Formatters.weight(item.weightKg))")
                                            .font(.system(size: 10, weight: .bold))
                                            .monospacedDigit()
                                        Text(Formatters.shortDate(item.recordedAt))
                                            .font(.system(size: 8))
                                            .opacity(0.85)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.62))
                                }
                                .frame(width: 66, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        isBefore && isAfter ? Color.purple : (isBefore ? Color.blue : (isAfter ? Color.green : Color.clear)),
                                        lineWidth: (isBefore || isAfter) ? 2.5 : 0
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .strongCard(padding: 12)
    }

    // MARK: - US-Navy Body Fat Lookup Near Date

    private func estimateBodyFat(near targetDate: Date) -> Double? {
        let maxWindowSeconds: TimeInterval = 21 * 86_400
        let candidates = wellnessStore.measurements.filter { m in
            guard let waist = m.waistCm, let neck = m.neckCm, waist > neck + 2 else { return false }
            return abs(m.recordedAt.timeIntervalSince(targetDate)) <= maxWindowSeconds
        }
        guard let closest = candidates.min(by: {
            abs($0.recordedAt.timeIntervalSince(targetDate)) < abs($1.recordedAt.timeIntervalSince(targetDate))
        }),
              let waist = closest.waistCm,
              let neck = closest.neckCm else {
            return nil
        }

        let heightCm = Double(max(130, nutritionStore.goals.heightCm))
        let denom = 1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(heightCm)
        guard denom > 0 else { return nil }
        let rawBF = (495.0 / denom) - 450.0
        return max(4.0, min(45.0, rawBF))
    }

    // MARK: - Share Card Export (iOS 16+ ImageRenderer)

    @MainActor
    private func renderShareCard() {
        guard let left = leftItem, let right = rightItem,
              let lImg = leftImage, let rImg = rightImage else {
            renderedShareImage = nil
            return
        }

        let card = TransformationShareCardView(
            beforeImage: lImg,
            afterImage: rImg,
            beforeWeightText: "\(Formatters.weight(left.weightKg)) kg",
            afterWeightText: "\(Formatters.weight(right.weightKg)) kg",
            beforeDateText: Formatters.shortDate(left.recordedAt),
            afterDateText: Formatters.shortDate(right.recordedAt),
            weightDiffText: weightDiffKg.map { diff in
                let sign = diff >= 0 ? "+" : ""
                return "\(sign)\(Formatters.weight(diff)) kg"
            },
            daysText: daysDiff.map { "\(abs($0)) Tage" },
            bodyFatDiffText: bodyFatDiffPercent.map { diff in
                let sign = diff >= 0 ? "+" : ""
                return String(format: "%@%.1f %% KFA", sign, diff).replacingOccurrences(of: ".", with: ",")
            }
        )

        let renderer = ImageRenderer(content: card.frame(width: 420))
        renderer.scale = 3.0
        renderedShareImage = renderer.uiImage
    }
}

// MARK: - Branded Share Card View

private struct TransformationShareCardView: View {
    let beforeImage: UIImage
    let afterImage: UIImage
    let beforeWeightText: String
    let afterWeightText: String
    let beforeDateText: String
    let afterDateText: String
    let weightDiffText: String?
    let daysText: String?
    let bodyFatDiffText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PEAKLOG TRANSFORMATION")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .tracking(1.1)
                        .foregroundColor(.cyan)
                    Text("Vorher / Nachher")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                if let days = daysText {
                    Text(days)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                sharePhotoColumn(tag: "VORHER", image: beforeImage, weight: beforeWeightText, date: beforeDateText, accent: .blue)
                sharePhotoColumn(tag: "NACHHER", image: afterImage, weight: afterWeightText, date: afterDateText, accent: .green)
            }

            HStack(spacing: 8) {
                if let diff = weightDiffText {
                    Text("Gewicht: \(diff)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.20))
                        .foregroundColor(.cyan)
                        .clipShape(Capsule())
                }
                if let bf = bodyFatDiffText {
                    Text(bf)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.22))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("PeakLog")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.24),
                    Color(red: 0.12, green: 0.20, blue: 0.45),
                    Color(red: 0.16, green: 0.12, blue: 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func sharePhotoColumn(tag: String, image: UIImage, weight: String, date: String, accent: Color) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 186, height: 270)
                .clipped()

            VStack {
                HStack {
                    Text(tag)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.88))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(8)

                Spacer()

                HStack {
                    Text(weight)
                        .font(.caption)
                        .fontWeight(.bold)
                    Spacer()
                    Text(date)
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.62))
            }
        }
        .frame(width: 186, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
