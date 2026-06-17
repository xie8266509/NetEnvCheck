import Foundation

struct SavedReport: Identifiable, Codable, Sendable {
    var id = UUID()
    var savedAt: Date
    var report: CheckReport

    var title: String {
        "\(report.riskScore) / 100 · \(report.publicIP ?? "--")"
    }
}

struct ComparisonItem: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var previous: String
    var current: String
    var isImportant: Bool
}

struct ReportComparison: Sendable {
    var previous: CheckReport
    var current: CheckReport

    var changes: [ComparisonItem] {
        var items: [ComparisonItem] = []

        appendChange(&items, id: "risk", title: "风险评分", previous: "\(previous.riskScore)", current: "\(current.riskScore)", important: true)
        appendChange(&items, id: "band", title: "风险等级", previous: previous.riskBand.title, current: current.riskBand.title, important: true)
        appendChange(&items, id: "ip", title: "出口 IP", previous: previous.publicIP ?? "--", current: current.publicIP ?? "--", important: true)
        appendChange(&items, id: "location", title: "归属地", previous: previous.locationDisplay, current: current.locationDisplay, important: true)
        appendChange(&items, id: "asn", title: "ASN", previous: previous.asnDisplay, current: current.asnDisplay, important: false)
        appendChange(&items, id: "ipv6", title: "IPv6", previous: previous.ipv6Address ?? "--", current: current.ipv6Address ?? "--", important: false)
        appendChange(&items, id: "dns", title: "DNS", previous: previous.dns.displayText, current: current.dns.displayText, important: false)
        appendChange(&items, id: "webrtc", title: "WebRTC", previous: previous.webRTCDisplay, current: current.webRTCDisplay, important: true)

        return items
    }

    private func appendChange(
        _ items: inout [ComparisonItem],
        id: String,
        title: String,
        previous: String,
        current: String,
        important: Bool
    ) {
        guard previous != current else { return }
        items.append(ComparisonItem(id: id, title: title, previous: previous, current: current, isImportant: important))
    }
}

struct HistoryStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = HistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() -> [SavedReport] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SavedReport].self, from: data)
                .sorted { $0.savedAt > $1.savedAt }
        } catch {
            return []
        }
    }

    @discardableResult
    func append(_ report: CheckReport, limit: Int = 100) -> [SavedReport] {
        var history = load()
        history.insert(SavedReport(savedAt: Date(), report: report), at: 0)
        history = Array(history.prefix(limit))
        save(history)
        return history
    }

    func save(_ history: [SavedReport]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NetEnvCheck history save failed: \(error.localizedDescription)")
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("NetEnvCheck", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
