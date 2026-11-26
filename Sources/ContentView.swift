import SwiftUI
import UIKit

struct ContentView: View {
    private var iosVersion: String {
        UIDevice.current.systemVersion
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)

                Text("StrongTracker bereit")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("iOS \(iosVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("StrongTracker")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
