import Testing
import CloudKit
import CookieCore
@testable import CookieSync

private let sep24 = CalendarDay(year: 2026, month: 9, day: 24)
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

struct TaskRecordTests {
    @Test func taskSurvivesTheRoundTrip() throws {
        let task = TaskItem(
            text: "Pay the electricity bill",
            day: sep24,
            order: 2.5,
            completedAt: t0 + 60,
            createdAt: t0,
            fieldTimes: FieldTimes(text: t0, placement: t0 + 1, completion: t0 + 60, deletion: t0)
        )
        let record = TaskRecord.record(for: task)
        #expect(record.recordID.recordName == task.id.uuidString)
        #expect(record.recordID.zoneID == TaskRecord.zoneID)
        #expect(try #require(TaskRecord.item(from: record)) == task)
    }

    @Test func clearingAFieldClearsItOnTheRecord() throws {
        var task = TaskItem(text: "Walk Cookie", day: sep24, order: 0, completedAt: t0, createdAt: t0)
        let record = TaskRecord.record(for: task)
        task.completedAt = nil
        TaskRecord.fill(record, from: task)
        #expect(try #require(TaskRecord.item(from: record)).completedAt == nil)
    }

    @Test func textIsStoredEncrypted() {
        let record = TaskRecord.record(for: TaskItem(text: "private", day: sep24, order: 0))
        #expect(record["text"] == nil)
        #expect(record.encryptedValues["text"] as String? == "private")
    }

    @Test func unreadableRecordsAreSkipped() {
        let record = CKRecord(recordType: TaskRecord.recordType,
                              recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: TaskRecord.zoneID))
        #expect(TaskRecord.item(from: record) == nil)
    }

    @Test func dayStringsRoundTrip() {
        #expect(sep24.isoString == "2026-09-24")
        #expect(CalendarDay(isoString: "2026-09-24") == sep24)
        #expect(CalendarDay(isoString: "garbage") == nil)
    }

    @Test func systemFieldsRoundTrip() throws {
        let record = TaskRecord.record(for: TaskItem(text: "x", day: sep24, order: 0))
        let restored = try #require(CKRecord.fromSystemFields(record.encodedSystemFields))
        #expect(restored.recordID == record.recordID)
        #expect(restored.recordType == record.recordType)
    }
}
