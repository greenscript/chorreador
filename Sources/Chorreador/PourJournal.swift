import Foundation

struct PourInterruption: Codable, Equatable {
    let sleptAt: Date
    let wokeAt: Date

    var duration: TimeInterval { wokeAt.timeIntervalSince(sleptAt) }
}

struct PourRecord: Codable, Equatable, Identifiable {
    enum EndReason: String, Codable {
        case finished
        case batteryPause
        case appQuit
    }

    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var sources: [String]
    var interruptions: [PourInterruption]
    var endReason: EndReason?
    // Refreshed while the pour is open so a record left dangling by a crash or
    // quit can be closed at a truthful timestamp on the next launch.
    var lastAliveAt: Date

    var isOpen: Bool { endedAt == nil }

    var totalSleepLost: TimeInterval {
        interruptions.reduce(0) { $0 + $1.duration }
    }

    func duration(asOf now: Date) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }
}

@MainActor
final class PourJournal: ObservableObject {
    @Published private(set) var records: [PourRecord] = []

    private let fileURL: URL
    private let maximumRecords = 60
    private let keepAlivePersistInterval: TimeInterval = 300
    private var lastPersistedAliveAt: Date?

    init(fileURL: URL = PourJournal.defaultFileURL()) {
        self.fileURL = fileURL
        load()
        closeDanglingRecord()
    }

    nonisolated static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Chorreador", isDirectory: true)
            .appendingPathComponent("pour-journal.json")
    }

    var openRecord: PourRecord? {
        records.last(where: \.isOpen)
    }

    var lastCompletedRecord: PourRecord? {
        records.last(where: { !$0.isOpen })
    }

    func beginPour(at date: Date, sources: [String]) {
        if openRecord != nil {
            endPour(at: date, reason: .finished)
        }
        records.append(
            PourRecord(
                id: UUID(),
                startedAt: date,
                endedAt: nil,
                sources: sources,
                interruptions: [],
                endReason: nil,
                lastAliveAt: date
            )
        )
        if records.count > maximumRecords {
            records.removeFirst(records.count - maximumRecords)
        }
        persist()
    }

    func updateSources(_ sources: [String], at date: Date) {
        guard let index = openRecordIndex() else { return }
        let merged = records[index].sources + sources.filter { !records[index].sources.contains($0) }
        records[index].lastAliveAt = date
        guard merged != records[index].sources else { return }
        records[index].sources = merged
        persist()
    }

    func recordInterruption(sleptAt: Date, wokeAt: Date) {
        guard let index = openRecordIndex() else { return }
        records[index].interruptions.append(
            PourInterruption(sleptAt: sleptAt, wokeAt: wokeAt)
        )
        records[index].lastAliveAt = wokeAt
        persist()
    }

    func endPour(at date: Date, reason: PourRecord.EndReason) {
        guard let index = openRecordIndex() else { return }
        records[index].endedAt = date
        records[index].endReason = reason
        records[index].lastAliveAt = date
        persist()
    }

    // Called on a slow tick while a pour is open; persists occasionally so the
    // dangling-record timestamp stays honest without hammering the disk.
    func keepAlive(at date: Date) {
        guard let index = openRecordIndex() else { return }
        records[index].lastAliveAt = date
        let lastPersisted = lastPersistedAliveAt ?? .distantPast
        if date.timeIntervalSince(lastPersisted) >= keepAlivePersistInterval {
            persist()
        }
    }

    func protectedDuration(from windowStart: Date, to windowEnd: Date) -> TimeInterval {
        var total: TimeInterval = 0
        for record in records {
            var spans: [(start: Date, end: Date)] = [
                (record.startedAt, record.endedAt ?? windowEnd)
            ]
            for interruption in record.interruptions {
                spans = spans.flatMap { span -> [(start: Date, end: Date)] in
                    guard interruption.sleptAt < span.end, interruption.wokeAt > span.start else {
                        return [span]
                    }
                    var pieces: [(start: Date, end: Date)] = []
                    if interruption.sleptAt > span.start {
                        pieces.append((span.start, interruption.sleptAt))
                    }
                    if interruption.wokeAt < span.end {
                        pieces.append((interruption.wokeAt, span.end))
                    }
                    return pieces
                }
            }
            for span in spans {
                let start = max(span.start, windowStart)
                let end = min(span.end, windowEnd)
                if end > start {
                    total += end.timeIntervalSince(start)
                }
            }
        }
        return total
    }

    private func openRecordIndex() -> Int? {
        records.lastIndex(where: \.isOpen)
    }

    private func closeDanglingRecord() {
        guard let index = openRecordIndex() else { return }
        records[index].endedAt = records[index].lastAliveAt
        records[index].endReason = .appQuit
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([PourRecord].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        lastPersistedAliveAt = openRecord?.lastAliveAt
    }
}

func brewDurationText(_ interval: TimeInterval) -> String {
    let totalMinutes = max(0, Int(interval) / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
    if minutes > 0 { return "\(minutes)m" }
    return "under 1m"
}
