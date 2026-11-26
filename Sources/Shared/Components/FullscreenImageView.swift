import SwiftUI
import UIKit

struct FullscreenImageView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    var caption: String? = nil

    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1.0, min(value, 4.0))
                            }
                            .onEnded { _ in
                                if scale < 1.1 {
                                    withAnimation(.spring()) {
                                        scale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1.0 ? 1.0 : 2.5
                        }
                    }

                if let caption = caption, !caption.isEmpty {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(.bottom, 24)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
