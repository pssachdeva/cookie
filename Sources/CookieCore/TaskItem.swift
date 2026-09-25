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
    /// deletion-versus-offline-edit are both resolvable.
    public var deletedAt: Date?
    public var createdAt: Date
    /// When each group of fields last changed, so two devices changing
    /// different parts of one task both keep their change (see `merged`).
    public var fieldTimes: FieldTimes
    /// The latest of `fieldTimes`.
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        day: CalendarDay,
        order: Double,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        fieldTimes: FieldTimes? = nil
    ) {
        self.id = id
        self.text = text
        self.day = day
        self.order = order
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.createdAt = createdAt.roundedToMilliseconds
        self.fieldTimes = fieldTimes ?? FieldTimes(all: modifiedAt.roundedToMilliseconds)
        self.modifiedAt = self.fieldTimes.latest
    }

    /// Files written before per-field times existed get `modifiedAt` for
    /// every field.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        day = try c.decode(CalendarDay.self, forKey: .day)
        order = try c.decode(Double.self, forKey: .order)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        fieldTimes = try c.decodeIfPresent(FieldTimes.self, forKey: .fieldTimes) ?? FieldTimes(all: modifiedAt)
    }

    public var isCompleted: Bool { completedAt != nil }
    public var isDeleted: Bool { deletedAt != nil }
    /// Visible in a list: neither deleted nor completed.
    public var isActive: Bool { !isCompleted && !isDeleted }

    /// Records a change to one group of fields.
    mutating func touch(_ field: FieldTimes.Field, at date: Date = .now) {
        fieldTimes[field] = date.roundedToMilliseconds
        modifiedAt = fieldTimes.latest
    }

    /// Combines two versions of the same task field group by field group:
    /// each group takes the value from whichever side changed it last.
    /// Deterministic on ties, so every device settles on the same result.
    public func merged(with other: TaskItem) -> TaskItem {
        precondition(id == other.id, "merging different tasks")
        var result = self

        if Self.otherWins(fieldTimes.text, other.fieldTimes.text, tie: other.text > text) {
            result.text = other.text
            result.fieldTimes.text = other.fieldTimes.text
        }
        if Self.otherWins(fieldTimes.placement, other.fieldTimes.placement,
                          tie: (other.day, other.order) > (day, order)) {
            result.day = other.day
            result.order = other.order
            result.fieldTimes.placement = other.fieldTimes.placement
        }
        if Self.otherWins(fieldTimes.completion, other.fieldTimes.completion,
                          tie: (other.completedAt ?? .distantPast) > (completedAt ?? .distantPast)) {
            result.completedAt = other.completedAt
            result.fieldTimes.completion = other.fieldTimes.completion
        }
        // On a tie, deleted beats not deleted.
        if Self.otherWins(fieldTimes.deletion, other.fieldTimes.deletion,
                          tie: (other.deletedAt ?? .distantPast) > (deletedAt ?? .distantPast)) {
            result.deletedAt = other.deletedAt
            result.fieldTimes.deletion = other.fieldTimes.deletion
        }
        result.createdAt = min(createdAt, other.createdAt)
        result.modifiedAt = result.fieldTimes.latest
        return result
    }

    private static func otherWins(_ mine: Date, _ theirs: Date, tie: Bool) -> Bool {
        theirs.isLater(than: mine) || (theirs.isSameInstant(as: mine) && tie)
    }
}

extension Date {
    /// Times closer than this are the same instant. The task file and
    /// CloudKit keep milliseconds and may truncate, so a time can come back
    /// up to a millisecond off; edits by hand are never this close.
    static let instantTolerance: TimeInterval = 0.002

    public func isLater(than other: Date) -> Bool {
        timeIntervalSince(other) > Self.instantTolerance
    }

    public func isSameInstant(as other: Date) -> Bool {
        abs(timeIntervalSince(other)) <= Self.instantTolerance
    }

    var roundedToMilliseconds: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1000).rounded() / 1000)
    }
}

/// Modification time for each independently mergeable group of fields.
public struct FieldTimes: Hashable, Codable, Sendable {
    public var text: Date
    /// Day and order, which always move together.
    public var placement: Date
    public var completion: Date
    public var deletion: Date

    public enum Field: CaseIterable, Sendable {
        case text, placement, completion, deletion
    }

    public init(text: Date, placement: Date, completion: Date, deletion: Date) {
        self.text = text
        self.placement = placement
        self.completion = completion
        self.deletion = deletion
    }

    public init(all date: Date) {
        self.init(text: date, placement: date, completion: date, deletion: date)
    }

    public var latest: Date { max(text, placement, completion, deletion) }

    public subscript(field: Field) -> Date {
        get {
            switch field {
            case .text: text
            case .placement: placement
            case .completion: completion
            case .deletion: deletion
            }
        }
        set {
            switch field {
            case .text: text = newValue
            case .placement: placement = newValue
            case .completion: completion = newValue
            case .deletion: deletion = newValue
            }
        }
    }
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
