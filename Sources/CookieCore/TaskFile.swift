import Foundation

/// Saves and loads all tasks as one JSON file. Saves are coalesced so a burst
/// of changes (a drag, a quick run of entries) writes once, and each write is
/// atomic, so a crash mid-write leaves the previous file intact.
@MainActor
public final class TaskFile {
    /// On-disk shape. The version lets a later format migrate older files.
    struct Archive: Codable {
        var version: Int
        var tasks: [TaskItem]
    }

    static let currentVersion = 1
    /// How long deleted tasks are kept before `TaskStore.purgeDeleted`
    /// erases them: long enough for undo and for the deletion to sync.
    public static let deletedRetention: TimeInterval = 30 * 86_400

    public let url: URL
    private let saveDelay: Duration
    private var pendingSave: Task<Void, Never>?

    public init(url: URL, saveDelay: Duration = .milliseconds(400)) {
        self.url = url
        self.saveDelay = saveDelay
    }

    /// `~/Library/Application Support/Cookie/tasks.json`, or `tasks.json` in
    /// `COOKIE_DATA_DIR` when set, so development runs can use scratch data.
    public static func defaultURL() -> URL {
        if let dir = ProcessInfo.processInfo.environment["COOKIE_DATA_DIR"], !dir.isEmpty {
            return URL(filePath: dir, directoryHint: .isDirectory).appending(path: "tasks.json")
        }
        return URL.applicationSupportDirectory
            .appending(path: "Cookie", directoryHint: .isDirectory)
            .appending(path: "tasks.json")
    }

    /// Reads the saved tasks. A missing file is an empty list. An unreadable
    /// file is moved aside (never overwritten) and the list starts empty, so
    /// its contents can still be recovered by hand.
    public func load(now: Date = .now) -> [TaskItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder.tasks.decode(Archive.self, from: data).tasks
        } catch {
            let stamp = Int(now.timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appending(path: "tasks-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return []
        }
    }

    /// Schedules a write of `tasks`, replacing any write still pending.
    public func scheduleSave(_ tasks: @escaping @MainActor () -> [TaskItem]) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.write(tasks())
        }
    }

    /// Writes immediately, cancelling any pending write. Used at quit.
    public func saveNow(_ tasks: [TaskItem]) {
        pendingSave?.cancel()
        pendingSave = nil
        write(tasks)
    }

    private func write(_ tasks: [TaskItem]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder.tasks.encode(Archive(version: Self.currentVersion, tasks: tasks))
            try data.write(to: url, options: .atomic)
        } catch {
            // Nothing sensible to show yet; the next change retries.
            print("Cookie: could not save tasks: \(error)")
        }
    }
}

/// ISO 8601 with milliseconds: whole seconds would tie tasks completed in
/// the same second, and the completed section is ordered by that time.
/// Written by hand because the formatter truncates rather than rounds, so
/// .578 can come out as .577.
enum TaskDateFormat {
    private static let wholeSeconds = Date.ISO8601FormatStyle()
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSinceReferenceDate * 1000).rounded()
        let seconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - seconds * 1000)
        let base = Date(timeIntervalSinceReferenceDate: seconds).formatted(wholeSeconds)
        return base.dropLast() + String(format: ".%03dZ", fraction)
    }

    static func date(from string: String) throws -> Date {
        try withFraction.parse(string)
    }
}

private extension JSONEncoder {
    static var tasks: JSONEncoder {
        let encoder = JSONEncoder()
        // Readable by hand, and stable so the file diffs cleanly.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TaskDateFormat.string(from: date))
        }
        return encoder
    }
}

private extension JSONDecoder {
    static var tasks: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try TaskDateFormat.date(from: text)
        }
        return decoder
    }
}
