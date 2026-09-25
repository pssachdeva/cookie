import Foundation

extension TaskStore {
    /// Sample data for the interaction prototype, laid out relative to
    /// `today` so the earlier-unfinished section, indicators, a long list,
    /// and a past month are all exercised.
    public static func sample(today: CalendarDay = .today()) -> TaskStore {
        let store = TaskStore()

        func add(_ text: String, _ offset: Int, done: Bool = false) {
            let day = today.adding(days: offset)
            if let item = store.add(text, to: day), done {
                store.setCompleted(item.id, true, at: day.date().addingTimeInterval(Double(36_000 + text.count * 60)))
            }
        }

        add("Reply to the landlord about the lease", -40)
        add("Book dentist appointment", -3)
        add("Return library books", -3, done: true)
        add("Send the reimbursement form", -1)
        add("Water the plants", -1, done: true)
        add("Call mom", -1, done: true)

        add("Plan the week", 0, done: true)
        add("Answer emails", 0, done: true)
        add("Buy groceries: eggs, spinach, coffee, oat milk, and the good bread from the bakery on College", 0)
        add("Walk Cookie", 0)
        add("Pay the electricity bill", 0)
        add("Read two chapters", 0)

        add("Prepare slides for Thursday", 1)
        add("Gym", 1)
        add("Pick up dry cleaning", 2)
        for i in 1...24 {
            add("Long-list item \(i)", 4)
        }
        add("Renew passport", 35)

        return store
    }
}
