import Charts
import SwiftUI
import UIKit

struct BodyweightView: View {
    @EnvironmentObject private var bodyweightStore: BodyweightStore

    enum ChartRange: String, CaseIterable, Identifiable {
        case days30 = "30T"
        case days90 = "90T"
        case all = "Alle"

        var id: String { rawValue }
    }

    @State private var selectedRange: ChartRange = .days90
    @State private var isShowingAddSheet: Bool = false
    @State private var editingEntry: BodyweightEntryWithPhotos? = nil
    @State private var isShowingCompareSheet: Bool = false
    @State private var fullscreenPhoto: (image: UIImage, caption: String)? = nil

    private var chartEntries: [BodyweightEntry] {
        let ascending = bodyweightStore.entries.map { $0.entry }.reversed()
        let now = Date()
        switch selectedRange {
        case .days30:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            return ascending.filter { $0.recordedAt >= cutoff }
        case .days90:
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
            return ascending.filter { $0.recordedAt >= cutoff }
        case .all:
            return Array(ascending)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let weights = chartEntries.map { $0.weightKg }
        guard let minW = weights.min(), let maxW = weights.max() else {
            return 60...100
        }
        let pad = max(1.0, (maxW - minW) * 0.2)
        return (minW - pad)...(maxW + pad)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryRow
                chartCard
                photoTimelineCard
                entriesListCard
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Körpergewicht & Fotos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Gewicht eintragen")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            BodyweightFormView(
                suggestedWeightKg: bodyweightStore.latestEntry?.entry.weightKg
            ) { entry, photos, removed in
                bodyweightStore.saveEntry(entry, photos: photos, removedFilenames: removed)
            }
        }
        .sheet(item: $editingEntry) { item in
            BodyweightFormView(existingEntry: item) { entry, photos, removed in
                bodyweightStore.saveEntry(entry, photos: photos, removedFilenames: removed)
            }
        }
        .sheet(isPresented: $isShowingCompareSheet) {
            PhotoCompareView(timeline: bodyweightStore.allPhotosTimeline)
        }
        .sheet(
            isPresented: Binding(
                get: { fullscreenPhoto != nil },
                set: { if !$0 { fullscreenPhoto = nil } }
            )
        ) {
            if let photo = fullscreenPhoto {
                FullscreenImageView(image: photo.image, caption: photo.caption)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            WeightStatCard(
                title: "Aktuell",
                value: bodyweightStore.latestEntry.map { "\(Formatters.weight($0.entry.weightKg)) kg" } ?? "–",
                accent: .accentColor
            )
            WeightStatCard(
                title: "Trend gesamt",
                value: formattedDelta,
                accent: deltaColor
            )
            WeightStatCard(
                title: "Fotos",
                value: "\(bodyweightStore.allPhotosTimeline.count)",
                accent: .purple
            )
        }
    }

    private var formattedDelta: String {
        guard let delta = bodyweightStore.deltaFromStartKg else { return "–" }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Formatters.weight(delta)) kg"
    }

    private var deltaColor: Color {
        guard let delta = bodyweightStore.deltaFromStartKg else { return .secondary }
        if abs(delta) < 0.1 { return .secondary }
        return delta < 0 ? .green : .orange
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gewichtsverlauf")
                    .font(.headline)
                Spacer()
                Picker("Zeitraum", selection: $selectedRange) {
                    ForEach(ChartRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 165)
            }

            if chartEntries.isEmpty {
                Text("Trage dein erstes Körpergewicht ein, um deinen Verlauf im Diagramm zu sehen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                Chart(chartEntries) { entry in
                    AreaMark(
                        x: .value("Datum", entry.recordedAt),
                        yStart: .value("Min", yDomain.lowerBound),
                        yEnd: .value("kg", entry.weightKg)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Datum", entry.recordedAt),
                        y: .value("kg", entry.weightKg)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Datum", entry.recordedAt),
                        y: .value("kg", entry.weightKg)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var photoTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fortschrittsfotos")
                    .font(.headline)
                Spacer()
                if bodyweightStore.allPhotosTimeline.count >= 2 {
                    Button {
                        isShowingCompareSheet = true
                    } label: {
                        Label("Vergleichen", systemImage: "square.split.2x1")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if bodyweightStore.allPhotosTimeline.isEmpty {
                Text("Füge bei einem Gewichtseintrag Fotos hinzu, um deine visuelle Entwicklung mit zugehörigem Gewicht festzuhalten.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bodyweightStore.allPhotosTimeline) { item in
                            if let image = MediaStorage.shared.loadImage(filename: item.photo.imageFilename, in: .bodyweight) {
                                Button {
                                    fullscreenPhoto = (image, item.labelText)
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 118, height: 158)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("\(Formatters.weight(item.weightKg)) kg")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                            Text(Formatters.shortDate(item.recordedAt))
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.55))
                                    }
                                    .frame(width: 118, height: 158)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strongCard()
    }

    private var entriesListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Einträge (\(bodyweightStore.entries.count))")
                    .font(.headline)
                Spacer()
                Button {
                    isShowingAddSheet = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            if bodyweightStore.entries.isEmpty {
                EmptyStateView(
                    systemImage: "scalemass",
                    title: "Noch keine Einträge",
                    message: "Starte dein Körpergewichtstracking mit deinem heutigen Gewicht und optionalen Fotos.",
                    actionTitle: "Ersten Eintrag anlegen"
                ) {
                    isShowingAddSheet = true
                }
            } else {
                ForEach(bodyweightStore.entries) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Formatters.weight(item.entry.weightKg)) kg")
                                    .font(.headline)
                                Text(Formatters.workoutDate(item.entry.recordedAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Menu {
                                Button {
                                    editingEntry = item
                                } label: {
                                    Label("Bearbeiten", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    bodyweightStore.deleteEntry(id: item.id)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let notes = item.entry.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !item.photos.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(item.photos) { photo in
                                    if let img = MediaStorage.shared.loadImage(filename: photo.imageFilename, in: .bodyweight) {
                                        Button {
                                            let cap = "\(Formatters.weight(item.entry.weightKg)) kg · \(Formatters.shortDate(item.entry.recordedAt))"
                                            fullscreenPhoto = (img, cap)
                                        } label: {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 56, height: 70)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
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

private struct WeightStatCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
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
