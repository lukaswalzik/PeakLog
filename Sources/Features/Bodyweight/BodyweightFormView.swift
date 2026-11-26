import PhotosUI
import SwiftUI
import UIKit

struct BodyweightFormView: View {
    @Environment(\.dismiss) private var dismiss

    struct DraftPhoto: Identifiable {
        let id: String
        var existingFilename: String?
        var image: UIImage
        var caption: String
        var createdAt: Date

        init(
            id: String = UUID().uuidString,
            existingFilename: String? = nil,
            image: UIImage,
            caption: String = "",
            createdAt: Date = Date()
        ) {
            self.id = id
            self.existingFilename = existingFilename
            self.image = image
            self.caption = caption
            self.createdAt = createdAt
        }
    }

    let existingEntry: BodyweightEntryWithPhotos?
    let suggestedWeightKg: Double?
    let onSave: (BodyweightEntry, [BodyweightPhoto], [String]) -> Void

    @State private var weightText: String
    @State private var recordedAt: Date
    @State private var notes: String
    @State private var draftPhotos: [DraftPhoto]
    @State private var removedFilenames: [String] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingCamera: Bool = false

    private let quickCaptions = ["Vorne", "Seite", "Rücken"]

    init(
        existingEntry: BodyweightEntryWithPhotos? = nil,
        suggestedWeightKg: Double? = nil,
        onSave: @escaping (BodyweightEntry, [BodyweightPhoto], [String]) -> Void
    ) {
        self.existingEntry = existingEntry
        self.suggestedWeightKg = suggestedWeightKg
        self.onSave = onSave

        if let existing = existingEntry {
            _weightText = State(initialValue: Formatters.weight(existing.entry.weightKg))
            _recordedAt = State(initialValue: existing.entry.recordedAt)
            _notes = State(initialValue: existing.entry.notes ?? "")
            let loadedPhotos: [DraftPhoto] = existing.photos.compactMap { photo in
                guard let img = MediaStorage.shared.loadImage(filename: photo.imageFilename, in: .bodyweight) else {
                    return nil
                }
                return DraftPhoto(
                    id: photo.id,
                    existingFilename: photo.imageFilename,
                    image: img,
                    caption: photo.caption ?? "",
                    createdAt: photo.createdAt
                )
            }
            _draftPhotos = State(initialValue: loadedPhotos)
        } else {
            _weightText = State(initialValue: suggestedWeightKg.map { Formatters.weight($0) } ?? "")
            _recordedAt = State(initialValue: Date())
            _notes = State(initialValue: "")
            _draftPhotos = State(initialValue: [])
        }
    }

    private var parsedWeight: Double? {
        guard let value = Formatters.parseWeight(weightText), value > 20, value < 350 else {
            return nil
        }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Gewicht & Datum")) {
                    HStack {
                        Text("Körpergewicht")
                        Spacer()
                        TextField("z. B. 82,5", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("kg")
                            .foregroundColor(.secondary)
                    }

                    DatePicker("Datum", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section(
                    header: Text("Fortschrittsfotos (\(draftPhotos.count))"),
                    footer: Text("Fotos werden diesem Gewichtseintrag zugeordnet und lokal auf dem Gerät gespeichert.")
                ) {
                    if !draftPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach($draftPhotos) { $photo in
                                    VStack(spacing: 6) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: photo.image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 110, height: 145)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                            Button {
                                                removePhoto(photo)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6).clipShape(Circle()))
                                            }
                                            .padding(6)
                                        }

                                        Menu {
                                            Button("Kein Tag") { photo.caption = "" }
                                            ForEach(quickCaptions, id: \.self) { tag in
                                                Button(tag) { photo.caption = tag }
                                            }
                                        } label: {
                                            Text(photo.caption.isEmpty ? "Pose wählen" : photo.caption)
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(uiColor: .tertiarySystemFill))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 5,
                            matching: .images
                        ) {
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
                    .padding(.vertical, 4)
                }

                Section(header: Text("Notizen (optional)")) {
                    TextField("z. B. morgens nüchtern, nach Urlaub", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existingEntry == nil ? "Gewicht eintragen" : "Eintrag bearbeiten")
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
                    .disabled(parsedWeight == nil)
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhotoItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    var loaded: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            loaded.append(image)
                        }
                    }
                    await MainActor.run {
                        for img in loaded {
                            draftPhotos.append(DraftPhoto(image: img))
                        }
                        selectedPhotoItems = []
                    }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPickerView { captured in
                    draftPhotos.append(DraftPhoto(image: captured))
                }
                .ignoresSafeArea()
            }
        }
    }

    private func removePhoto(_ photo: DraftPhoto) {
        if let existingFilename = photo.existingFilename {
            removedFilenames.append(existingFilename)
        }
        draftPhotos.removeAll { $0.id == photo.id }
    }

    private func save() {
        guard let weight = parsedWeight else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryId = existingEntry?.entry.id ?? UUID().uuidString

        let entry = BodyweightEntry(
            id: entryId,
            recordedAt: recordedAt,
            weightKg: weight,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        var savedPhotos: [BodyweightPhoto] = []
        for draft in draftPhotos {
            let filename: String?
            if let existing = draft.existingFilename {
                filename = existing
            } else {
                filename = try? MediaStorage.shared.saveImage(draft.image, in: .bodyweight, maxDimension: 1400)
            }
            if let filename = filename {
                savedPhotos.append(
                    BodyweightPhoto(
                        id: draft.id,
                        entryId: entryId,
                        imageFilename: filename,
                        caption: draft.caption.isEmpty ? nil : draft.caption,
                        createdAt: draft.createdAt
                    )
                )
            }
        }

        onSave(entry, savedPhotos, removedFilenames)
        dismiss()
    }
}
