import Foundation
import UIKit

enum MediaFolder: String {
    case exercises = "Exercises"
    case bodyweight = "Bodyweight"
}

final class MediaStorage {
    static let shared = MediaStorage()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    private init() {
        cache.countLimit = 120
    }

    private func folderURL(for folder: MediaFolder) throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupportURL
            .appendingPathComponent("StrongTracker", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(folder.rawValue, isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheKey(filename: String, folder: MediaFolder) -> NSString {
        "\(folder.rawValue)/\(filename)" as NSString
    }

    func saveImage(
        _ image: UIImage,
        in folder: MediaFolder,
        maxDimension: CGFloat = 1200,
        compressionQuality: CGFloat = 0.82
    ) throws -> String {
        let resized = downscale(image: image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: compressionQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let filename = "\(UUID().uuidString).jpg"
        let url = try folderURL(for: folder).appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        cache.setObject(resized, forKey: cacheKey(filename: filename, folder: folder))
        return filename
    }

    func loadImage(filename: String?, in folder: MediaFolder) -> UIImage? {
        guard let filename = filename, !filename.isEmpty else { return nil }
        let key = cacheKey(filename: filename, folder: folder)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let url = try? folderURL(for: folder).appendingPathComponent(filename),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func loadBundledExerciseImage(exerciseId: String) -> UIImage? {
        let key = "Bundled/\(exerciseId)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let url = Bundle.main.url(forResource: exerciseId, withExtension: "jpg", subdirectory: "ExerciseImages")
            ?? Bundle.main.url(forResource: exerciseId, withExtension: "jpg")

        guard let fileURL = url,
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func loadExerciseImage(for exercise: Exercise) -> UIImage? {
        if let custom = loadImage(filename: exercise.imageFilename, in: .exercises) {
            return custom
        }
        return loadBundledExerciseImage(exerciseId: exercise.id)
    }

    func deleteImage(filename: String?, in folder: MediaFolder) {
        guard let filename = filename, !filename.isEmpty else { return }
        cache.removeObject(forKey: cacheKey(filename: filename, folder: folder))
        if let url = try? folderURL(for: folder).appendingPathComponent(filename) {
            try? fileManager.removeItem(at: url)
        }
    }

    func loadRawData(filename: String, in folder: MediaFolder) -> Data? {
        guard let url = try? folderURL(for: folder).appendingPathComponent(filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    func saveRawData(_ data: Data, filename: String, in folder: MediaFolder) throws {
        let url = try folderURL(for: folder).appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        cache.removeObject(forKey: cacheKey(filename: filename, folder: folder))
    }

    private func downscale(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else {
            return image
        }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
