import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

enum ReportExportFormat {
    case markdown
    case json

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .json:
            "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .json:
            "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown:
            UTType(filenameExtension: "md") ?? .plainText
        case .json:
            .json
        }
    }
}

extension Notification.Name {
    static let netEnvCheckReportDidChange = Notification.Name("NetEnvCheckReportDidChange")
    static let netEnvCheckRefreshStateDidChange = Notification.Name("NetEnvCheckRefreshStateDidChange")
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var report = CheckReport()
    @Published var history: [SavedReport]
    @Published var comparison: ReportComparison?
    @Published var isRefreshing = false
    @Published var webRTCPending = false
    @Published var refreshToken = UUID()
    @Published var lastActionMessage: String?
    @Published var selectedPreset: RiskPreset = .balanced {
        didSet {
            report.scoringPreset = selectedPreset
            updateComparisonAgainstLatest()
            postReportUpdate()
        }
    }

    private let service = ProbeService()
    private let historyStore = HistoryStore()
    private var didStart = false

    private init() {
        history = historyStore.load()
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        NotificationService.shared.requestAuthorization()

        Task {
            await refresh()
        }
    }

    func refresh() async {
        isRefreshing = true
        webRTCPending = true
        lastActionMessage = nil
        postRefreshStateUpdate()

        var nextReport = await service.run(preset: selectedPreset)
        nextReport.webRTCSupported = nil
        nextReport.webRTCCandidates = []
        nextReport.browser = BrowserEnvironment()

        report = nextReport
        refreshToken = UUID()
        isRefreshing = false
        updateComparisonAgainstLatest()
        postReportUpdate()
        postRefreshStateUpdate()
    }

    func applyWebRTC(_ payload: WebRTCProbePayload) {
        report.webRTCSupported = payload.supported
        report.webRTCCandidates = payload.candidates
        report.browser = payload.browser

        if let error = payload.error, !error.isEmpty {
            report.errors.append("WebRTC：\(error)")
        }

        if let error = payload.browser.error, !error.isEmpty {
            report.errors.append("浏览器环境：\(error)")
        }

        webRTCPending = false
        persistCompletedReport()
        postReportUpdate()
        postRefreshStateUpdate()
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.plainTextReport(), forType: .string)
        lastActionMessage = "报告已复制"
    }

    func exportCurrentReport(as format: ReportExportFormat) {
        let panel = NSSavePanel()
        panel.title = "导出\(format.title)报告"
        panel.nameFieldStringValue = "NetEnvCheck-\(Self.fileTimestamp()).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data: Data
            switch format {
            case .markdown:
                data = Data(report.markdownReport().utf8)
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                data = try encoder.encode(report)
            }

            try data.write(to: url, options: .atomic)
            lastActionMessage = "已导出 \(format.title)"
        } catch {
            lastActionMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func restore(_ savedReport: SavedReport) {
        selectedPreset = savedReport.report.scoringPreset
        report = savedReport.report
        webRTCPending = false
        isRefreshing = false
        updateComparisonAgainstLatest()
        postReportUpdate()
        postRefreshStateUpdate()
    }

    private func persistCompletedReport() {
        let previous = history.first?.report
        let completed = report

        if let previous {
            comparison = ReportComparison(previous: previous, current: completed)
            NotificationService.shared.notifyIfNeeded(previous: previous, current: completed)
        }

        history = historyStore.append(completed)
    }

    private func updateComparisonAgainstLatest() {
        guard let previous = history.first?.report else {
            comparison = nil
            return
        }

        comparison = ReportComparison(previous: previous, current: report)
    }

    private func postReportUpdate() {
        NotificationCenter.default.post(name: .netEnvCheckReportDidChange, object: report)
    }

    private func postRefreshStateUpdate() {
        NotificationCenter.default.post(name: .netEnvCheckRefreshStateDidChange, object: nil)
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(previous: CheckReport, current: CheckReport) {
        let scoreDropped = current.riskScore + 10 <= previous.riskScore
        let ipChanged = previous.publicIP != current.publicIP
        let bandWorse = severity(current.riskBand) > severity(previous.riskBand)

        guard scoreDropped || ipChanged || bandWorse else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "NetEnvCheck 环境变化"
        content.body = notificationBody(previous: previous, current: current)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "netenvcheck-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notificationBody(previous: CheckReport, current: CheckReport) -> String {
        if previous.publicIP != current.publicIP {
            return "出口 IP 从 \(previous.publicIP ?? "--") 变为 \(current.publicIP ?? "--")，当前评分 \(current.riskScore)。"
        }

        return "风险从 \(previous.riskScore) 变为 \(current.riskScore)，当前为\(current.riskBand.title)。"
    }

    private func severity(_ band: RiskBand) -> Int {
        switch band {
        case .unknown:
            0
        case .low:
            1
        case .medium:
            2
        case .high:
            3
        }
    }
}
