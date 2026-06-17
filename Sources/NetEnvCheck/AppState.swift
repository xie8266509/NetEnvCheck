import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

enum ReportExportFormat {
    case markdown
    case json
    case html

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .json:
            "JSON"
        case .html:
            "HTML"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .json:
            "json"
        case .html:
            "html"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown:
            UTType(filenameExtension: "md") ?? .plainText
        case .json:
            .json
        case .html:
            .html
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
    @Published var settings: AppSettings
    @Published var ipinfoToken: String
    @Published var isRefreshing = false
    @Published var webRTCPending = false
    @Published var refreshToken = UUID()
    @Published var lastActionMessage: String?
    @Published var selectedPreset: RiskPreset = .balanced {
        didSet {
            report.scoringPreset = selectedPreset
            if settings.defaultPreset != selectedPreset {
                settings.defaultPreset = selectedPreset
                settingsStore.save(settings)
            }
            updateComparisonAgainstLatest()
            postReportUpdate()
        }
    }

    private let service = ProbeService()
    private let historyStore = HistoryStore()
    private let settingsStore = SettingsStore()
    private var didStart = false
    private var autoRefreshTask: Task<Void, Never>?

    private init() {
        let loadedSettings = settingsStore.load()
        settings = loadedSettings
        ipinfoToken = KeychainStore.loadIPinfoToken()
        selectedPreset = loadedSettings.defaultPreset
        history = Array(historyStore.load().prefix(loadedSettings.historyLimit))
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        if settings.notificationsEnabled {
            NotificationService.shared.requestAuthorization()
        }
        configureAutoRefresh()

        Task {
            await refresh()
        }
    }

    func refresh() async {
        isRefreshing = true
        webRTCPending = true
        lastActionMessage = nil
        postRefreshStateUpdate()

        var nextReport = await service.run(preset: selectedPreset, settings: settings, ipinfoToken: ipinfoToken)

        if settings.isEnabled(.webRTC) || settings.isEnabled(.httpHeaders) {
            nextReport.webRTCSupported = nil
            nextReport.webRTCCandidates = []
            nextReport.browser = BrowserEnvironment()
            webRTCPending = true
        } else {
            nextReport.webRTCSupported = false
            nextReport.webRTCCandidates = []
            nextReport.browser = BrowserEnvironment()
            webRTCPending = false
        }

        report = nextReport
        refreshToken = UUID()
        isRefreshing = false
        updateComparisonAgainstLatest()
        postReportUpdate()
        postRefreshStateUpdate()
    }

    func applyWebRTC(_ payload: WebRTCProbePayload) {
        guard settings.isEnabled(.webRTC) || settings.isEnabled(.httpHeaders) else {
            webRTCPending = false
            persistCompletedReport()
            return
        }

        report.webRTCSupported = payload.supported
        report.webRTCCandidates = settings.isEnabled(.webRTC) ? payload.candidates : []
        report.browser = settings.isEnabled(.httpHeaders) ? payload.browser : BrowserEnvironment()

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

    func copyText(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastActionMessage = message
    }

    func showMessage(_ message: String) {
        lastActionMessage = message
    }

    func copyRemediationGuide() {
        copyText(report.remediationGuide(), message: "修复方案已复制")
    }

    func openSystemSettings(_ destination: SystemSettingsDestination) {
        let didOpen = SystemSettingsOpener.open(destination)
        lastActionMessage = didOpen ? "已打开\(destination.title)" : "无法打开系统设置"
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
            case .html:
                data = Data(report.htmlReport().utf8)
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

    func deleteHistoryItem(_ savedReport: SavedReport) {
        history = historyStore.delete(id: savedReport.id)
        updateComparisonAgainstLatest()
    }

    func clearHistory() {
        historyStore.clear()
        history = []
        comparison = nil
        lastActionMessage = "历史记录已清空"
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var next = settings
        transform(&next)
        next = next.normalized
        settings = next
        selectedPreset = next.defaultPreset
        settingsStore.save(next)
        history = Array(history.prefix(next.historyLimit))

        if next.notificationsEnabled {
            NotificationService.shared.requestAuthorization()
        }

        configureAutoRefresh()
    }

    func updateIPinfoToken(_ token: String) {
        ipinfoToken = token
        KeychainStore.saveIPinfoToken(token)
        lastActionMessage = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "IPinfo Token 已清空" : "IPinfo Token 已保存"
    }

    private func persistCompletedReport() {
        let previous = history.first?.report
        let completed = report

        if let previous {
            comparison = ReportComparison(previous: previous, current: completed)
            if settings.notificationsEnabled {
                NotificationService.shared.notifyIfNeeded(previous: previous, current: completed)
            }
        }

        history = historyStore.append(completed, limit: settings.historyLimit)
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

    private func configureAutoRefresh() {
        autoRefreshTask?.cancel()
        guard settings.autoRefreshEnabled else { return }

        let interval = UInt64(settings.autoRefreshIntervalMinutes * 60) * 1_000_000_000
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
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
