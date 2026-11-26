import SwiftUI

struct RestTimerBarView: View {
    @ObservedObject var timerManager: RestTimerManager

    private var formattedCountdown: String {
        let mins = timerManager.remainingSeconds / 60
        let secs = timerManager.remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: timerManager.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    Text(formattedCountdown)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }

                Spacer()

                Button("-15s") {
                    timerManager.adjust(by: -15)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("+15s") {
                    timerManager.adjust(by: 15)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Skip") {
                    timerManager.skip()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .overlay(
            Divider(),
            alignment: .top
        )
    }
}

struct RestTimerBarView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = RestTimerManager()
        RestTimerBarView(timerManager: manager)
    }
}
