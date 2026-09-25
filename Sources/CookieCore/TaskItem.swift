import Foundation

/// One checklist row. Named `TaskItem` to avoid colliding with Swift
/// concurrency's `Task`.
public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var text: String
    /// The day this task belongs to. Completing it never changes this.
    public var day: CalendarDay
    /// Position within the day's list. Fractional so an insert or move
    /// rewrites one task instead of renumbering the day. Kept on completion
    /// so unchecking restores the old position.
    public var order: Double
    public var completedAt: Date?
    /// Deleted marker rather than an erased record, so undo and
    /// deletion-versus-offline-edit are both resolvable later.
    public var deletedAt: Date?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        day: CalendarDay,
        order: Double,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.day = day
        self.order = order
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var isCompleted: Bool { completedAt != nil }
    public var isDeleted: Bool { deletedAt != nil }
    /// Visible in a list: neither deleted nor completed.
    public var isActive: Bool { !isCompleted && !isDeleted }
}

public enum TaskText {
    public static let maxLength = 1000

    /// Normalizes entry text: line breaks become single spaces,
    /// surrounding whitespace is trimmed, the result is capped at
    /// `maxLength`. Returns nil when nothing remains.
    public static func normalized(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }
}

/// Where new tasks go within a day's list.
public enum Insertion: String, Codable, Sendable, CaseIterable {
    case top
    case bottom
}

/// Fractional ordering keys. Stable ID is the tie-break when two keys match.
public enum OrderKey {
    public static let step: Double = 1

    public static func between(_ lower: Double?, _ upper: Double?) -> Double {
        switch (lower, upper) {
        case (nil, nil): return 0
        case (let lo?, nil): return lo + step
        case (nil, let hi?): return hi - step
        case (let lo?, let hi?): return (lo + hi) / 2
        }
    }
}
