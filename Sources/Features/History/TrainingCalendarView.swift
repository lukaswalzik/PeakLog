import SwiftUI

struct TrainingCalendarView: View {
    let strengthDates: [Date]
    let cardioDates: [Date]

    @State private var displayedMonth: Date = Date()

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        cal.locale = Locale(identifier: "de_DE")
        return cal
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private let weekdaySymbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    private var strengthDaySet: Set<Date> {
        Set(strengthDates.map { calendar.startOfDay(for: $0) })
    }

    private var cardioDaySet: Set<Date> {
        Set(cardioDates.map { calendar.startOfDay(for: $0) })
    }

    private var monthGridDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstDay = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        // Convert Sunday=1...Saturday=7 to Monday=0...Sunday=6
        let leadingEmpty = (weekday + 5) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(6)
                }

                Spacer()

                Text(Self.monthYearFormatter.string(from: displayedMonth).capitalized)
                    .font(.subheadline)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(6)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let start = calendar.startOfDay(for: date)
                        let hasStrength = strengthDaySet.contains(start)
                        let hasCardio = cardioDaySet.contains(start)
                        let isToday = calendar.isDateInToday(date)

                        VStack(spacing: 3) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.caption)
                                .fontWeight(isToday ? .bold : .regular)
                                .foregroundColor(isToday ? .white : .primary)
                                .frame(width: 26, height: 26)
                                .background(isToday ? Color.accentColor : Color.clear)
                                .clipShape(Circle())

                            HStack(spacing: 3) {
                                if hasStrength {
                                    Circle().fill(Color.blue).frame(width: 5, height: 5)
                                }
                                if hasCardio {
                                    Circle().fill(Color.green).frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 6)
                        }
                    } else {
                        Color.clear.frame(height: 35)
                    }
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                    Text("Kraft")
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("Cardio")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .strongCard(padding: 12)
    }

    private func shiftMonth(by months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = next
        }
    }
}
