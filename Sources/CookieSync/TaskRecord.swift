import CloudKit
import CookieCore

/// How a task is stored in CloudKit: one `Task` record per task, named by
/// the task's ID, in a custom zone of the user's private database.
public enum TaskRecord {
    public static let recordType = "Task"
    public static let zoneID = CKRecordZone.ID(zoneName: "Tasks", ownerName: CKCurrentUserDefaultName)

    enum Key {
        static let text = "text"
        static let day = "day"
        static let order = "order"
        static let completedAt = "completedAt"
        static let deletedAt = "deletedAt"
        static let createdAt = "createdAt"
        static let textModified = "textModified"
        static let placementModified = "placementModified"
        static let completionModified = "completionModified"
        static let deletionModified = "deletionModified"
    }

    public static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    public static func taskID(of recordID: CKRecord.ID) -> UUID? {
        UUID(uuidString: recordID.recordName)
    }

    /// Writes `item` into `record`, which is either new or rebuilt from the
    /// server's last copy (so CloudKit can tell whether it is up to date).
    public static func fill(_ record: CKRecord, from item: TaskItem) {
        // The text is end-to-end encrypted: readable only on the user's
        // devices, not by Apple.
        record.encryptedValues[Key.text] = item.text
        record[Key.day] = item.day.isoString
        record[Key.order] = item.order
        record[Key.completedAt] = item.completedAt
        record[Key.deletedAt] = item.deletedAt
        record[Key.createdAt] = item.createdAt
        record[Key.textModified] = item.fieldTimes.text
        record[Key.placementModified] = item.fieldTimes.placement
        record[Key.completionModified] = item.fieldTimes.completion
        record[Key.deletionModified] = item.fieldTimes.deletion
    }

    public static func record(for item: TaskItem) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: item.id))
        fill(record, from: item)
        return record
    }

    /// Reads a task back, or nil for a record this version can't read.
    public static func item(from record: CKRecord) -> TaskItem? {
        guard record.recordType == recordType,
              let id = taskID(of: record.recordID),
              let text: String = record.encryptedValues[Key.text],
              let dayString = record[Key.day] as? String,
              let day = CalendarDay(isoString: dayString),
              let order = record[Key.order] as? Double,
              let createdAt = record[Key.createdAt] as? Date,
              let textModified = record[Key.textModified] as? Date,
              let placementModified = record[Key.placementModified] as? Date,
              let completionModified = record[Key.completionModified] as? Date,
              let deletionModified = record[Key.deletionModified] as? Date
        else { return nil }
        return TaskItem(
            id: id,
            text: text,
            day: day,
            order: order,
            completedAt: record[Key.completedAt] as? Date,
            deletedAt: record[Key.deletedAt] as? Date,
            createdAt: createdAt,
            fieldTimes: FieldTimes(
                text: textModified,
                placement: placementModified,
                completion: completionModified,
                deletion: deletionModified
            )
        )
    }
}

extension CalendarDay {
    /// "2026-09-24". A plain string, not a `Date`, so the day can't shift
    /// with time zones on its way through the server.
    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}

extension CKRecord {
    /// The server bookkeeping (change tag and so on) without the fields, so
    /// a later save can be rebuilt on top of it.
    var encodedSystemFields: Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func fromSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
