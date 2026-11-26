import SwiftUI

struct RemindersSettingsView: View {
    @ObservedObject private var manager = ReminderManager.shared

    var body: some View {
        Form {
            Section(
                header: Text("Supplements (z. B. Kreatin)"),
                footer: Text("Alle Erinnerungen laufen 100 % lokal auf deinem iPhone ohne Server.")
            ) {
                Toggle("Tägliche Supplement-Erinnerung", isOn: $manager.supplementEnabled)
                if manager.supplementEnabled {
                    DatePicker("Uhrzeit", selection: $manager.supplementTime, displayedComponents: .hourAndMinute)
                }
            }

            Section(header: Text("Wasserziel")) {
                Toggle("Tägliche Wasser-Erinnerung", isOn: $manager.waterEnabled)
                if manager.waterEnabled {
                    DatePicker("Uhrzeit", selection: $manager.waterTime, displayedComponents: .hourAndMinute)
                }
            }

            Section(header: Text("Training")) {
                Toggle("Tägliche Trainings-Erinnerung", isOn: $manager.workoutEnabled)
                if manager.workoutEnabled {
                    DatePicker("Uhrzeit", selection: $manager.workoutTime, displayedComponents: .hourAndMinute)
                }
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
