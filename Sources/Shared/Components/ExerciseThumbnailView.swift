import SwiftUI
import UIKit

struct ExerciseThumbnailView: View {
    let exercise: Exercise
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let image = MediaStorage.shared.loadExerciseImage(for: exercise) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.75)
                    )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            exercise.muscleGroup.accentColor.opacity(0.24),
                            exercise.muscleGroup.accentColor.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: exercise.muscleGroup.systemImage)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundColor(exercise.muscleGroup.accentColor)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(exercise.muscleGroup.accentColor.opacity(0.22), lineWidth: 0.75)
                )
            }
        }
    }
}
