import Foundation

/// What the PocketBook writes over BLE (README §7).
struct Payload: Decodable {
    let v: Int
    let document: String
    let progress: String
    let percentage: Double
    let device: String
    let device_id: String
    let title: String?
    let author: String?
    let captured_at: Int
    let sent_at: Int
}

struct ProgressEntry: Codable, Identifiable {
    enum Status: Codable, Equatable {
        case pending
        case sent(Date)
        case skippedServerNewer
        case failed(String)
    }

    var document: String
    var progress: String
    var percentage: Double
    var device: String
    var deviceId: String
    var title: String?
    var author: String?
    /// When the page was actually read, on the iPhone's clock.
    var readAt: Date
    var receivedAt: Date
    var status: Status

    var id: String { document }
    var isPending: Bool {
        if case .sent = status { return false }
        return status != .skippedServerNewer
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var entries: [String: ProgressEntry] = [:]

    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("progress.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: ProgressEntry].self, from: data) {
            entries = saved
        }
    }

    var sorted: [ProgressEntry] { entries.values.sorted { $0.readAt > $1.readAt } }
    var pending: [ProgressEntry] { entries.values.filter(\.isPending) }

    func receive(_ p: Payload, at now: Date = Date()) {
        // The PocketBook clock may be off: only the gap between capture and send is trusted.
        let readAt = now.addingTimeInterval(-Double(max(0, p.sent_at - p.captured_at)))
        if let existing = entries[p.document], existing.readAt >= readAt { return }
        entries[p.document] = ProgressEntry(
            document: p.document, progress: p.progress, percentage: p.percentage,
            device: p.device, deviceId: p.device_id,
            title: p.title.flatMap { $0.isEmpty ? nil : $0 }, author: p.author.flatMap { $0.isEmpty ? nil : $0 }, readAt: readAt, receivedAt: now, status: .pending)
        save()
    }

    func setStatus(_ status: ProgressEntry.Status, for document: String, readAt: Date) {
        // Ignore if a newer progress arrived while the request was in flight.
        guard entries[document]?.readAt == readAt else { return }
        entries[document]?.status = status
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
