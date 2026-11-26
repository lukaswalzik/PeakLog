import SwiftUI

struct HeartRateZoneBarView: View {
    let session: CardioSession
    var height: CGFloat = 10

    var body: some View {
        let total = session.totalZoneSeconds
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(HeartRateZone.allCases) { zone in
                        let secs = session.seconds(for: zone)
                        if secs > 0 {
                            let fraction = CGFloat(secs) / CGFloat(total)
                            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                                .fill(zone.color)
                                .frame(width: max(4, geo.size.width * fraction - 2))
                        }
                    }
                }
            }
            .frame(height: height)
        }
    }
}
