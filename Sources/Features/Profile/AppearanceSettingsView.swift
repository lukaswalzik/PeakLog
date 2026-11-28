import SwiftUI
import UIKit

struct AppearanceSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        List {
            Section {
                previewCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section(header: Text("Erscheinungsbild")) {
                HStack(spacing: 10) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        let selected = themeManager.appearance == mode
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            themeManager.appearance = mode
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: mode.systemImage)
                                    .font(.title3)
                                Text(mode.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selected ? themeManager.preset.accentColor.opacity(0.16) : Color(uiColor: .tertiarySystemFill))
                            .foregroundColor(selected ? themeManager.preset.accentColor : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? themeManager.preset.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Farb-Design")) {
                ForEach(AppThemePreset.allCases) { preset in
                    let selected = themeManager.preset == preset
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        themeManager.preset = preset
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(preset.heroGradient)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(preset.accentColor)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(
                header: Text("Aufgeräumte Ansicht"),
                footer: Text("Im Fokus-Modus bleiben der Cardio-Plan und Details auf dem Startbildschirm platzsparend eingeklappt und öffnen sich mit einem Tipp.")
            ) {
                Toggle("Aufgeräumter Startbildschirm", isOn: $themeManager.compactStartScreen)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Design & Erscheinungsbild")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PeakLog · \(themeManager.preset.displayName)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.20))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                Spacer()
                Text(themeManager.appearance.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.85))
            }

            Text("Bereit fürs Training?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            HStack(spacing: 10) {
                Text("Kraft starten")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(themeManager.preset.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Cardio")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(themeManager.preset.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
