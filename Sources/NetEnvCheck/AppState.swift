import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

enum ReportExportFormat {
    case markdown
    case json
    case html
    case optimization

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .json:
            "JSON"
        case .html:
            "HTML"
        case .optimization:
            "优化报告"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown, .optimization:
            "md"
        case .json:
            "json"
        case .html:
            "html"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown, .optimization:
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
    @Published var latestUpdate: UpdateRelease?
    @Published var updateErrorMessage: String?
    @Published var downloadedUpdateURL: URL?
    @Published var downloadedUpdate: DownloadedUpdate?
    @Published var isCheckingForUpdates = false
    @Published var isDownloadingUpdate = false
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

        if shouldCheckForUpdatesAutomatically {
            Task {
                await checkForUpdates(userInitiated: false)
            }
        }
    }

    var currentVersionText: String {
        UpdateChecker.currentVersion
    }

    var shouldCheckForUpdatesAutomatically: Bool {
        guard settings.automaticUpdateChecksEnabled else { return false }
        guard let lastUpdateCheckAt = settings.lastUpdateCheckAt else { return true }
        return Date().timeIntervalSince(lastUpdateCheckAt) >= 24 * 60 * 60
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
            report.errors.append("WebRTC：\(FriendlyErrorMessage.text(error, source: "WebRTC"))")
        }

        if let error = payload.browser.error, !error.isEmpty {
            report.errors.append("浏览器环境：\(FriendlyErrorMessage.text(error, source: "浏览器环境"))")
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

    func checkForUpdates(userInitiated: Bool) async {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        updateErrorMessage = nil
        if userInitiated {
            lastActionMessage = "正在检查更新"
        }

        defer {
            isCheckingForUpdates = false
        }

        do {
            let release = try await UpdateChecker.checkLatestRelease(currentVersion: currentVersionText)
            latestUpdate = release
            markUpdateChecked()

            if release.isNewerThanCurrent {
                lastActionMessage = "发现新版本 \(release.tagName)"
                if userInitiated || shouldPresentAutomaticUpdate(release) {
                    presentUpdateAvailableAlert(release)
                }
            } else {
                lastActionMessage = "已是最新版本"
                if userInitiated {
                    presentNoUpdateAlert(release)
                }
            }
        } catch {
            let message = error.localizedDescription
            updateErrorMessage = message
            markUpdateChecked()
            lastActionMessage = "检查更新失败"
            if userInitiated {
                presentUpdateErrorAlert(message)
            }
        }
    }

    func openLatestReleasePage() {
        if let latestUpdate {
            NSWorkspace.shared.open(latestUpdate.htmlURL)
        } else if let url = URL(string: "https://github.com/\(UpdateChecker.repository)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    func ignoreUpdate(_ release: UpdateRelease) {
        updateSettings { settings in
            settings.ignoredUpdateVersion = release.tagName
            settings.updateReminderAfter = nil
        }
        lastActionMessage = "已忽略 \(release.tagName)"
    }

    func remindUpdateLater(_ release: UpdateRelease) {
        updateSettings { settings in
            settings.updateReminderAfter = Date().addingTimeInterval(24 * 60 * 60)
            if settings.ignoredUpdateVersion == release.tagName {
                settings.ignoredUpdateVersion = nil
            }
        }
        lastActionMessage = "明天再提醒"
    }

    func revealDownloadedUpdate() {
        guard let downloadedUpdateURL else {
            lastActionMessage = "暂无下载包"
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([downloadedUpdateURL])
    }

    func downloadLatestUpdate() async {
        if let latestUpdate {
            await downloadUpdate(latestUpdate)
            return
        }

        await checkForUpdates(userInitiated: true)
        if let latestUpdate, latestUpdate.isNewerThanCurrent {
            await downloadUpdate(latestUpdate)
        }
    }

    func downloadUpdate(_ release: UpdateRelease) async {
        guard !isDownloadingUpdate else { return }

        isDownloadingUpdate = true
        lastActionMessage = "正在下载更新"

        defer {
            isDownloadingUpdate = false
        }

        do {
            let downloaded = try await UpdateChecker.downloadAppZip(from: release)
            downloadedUpdate = downloaded
            downloadedUpdateURL = downloaded.fileURL
            lastActionMessage = "更新包已下载"
            NSWorkspace.shared.activateFileViewerSelecting([downloaded.fileURL])
            presentUpdateDownloadedAlert(downloaded)
        } catch {
            lastActionMessage = "下载更新失败"
            presentUpdateErrorAlert(error.localizedDescription)
        }
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
            case .optimization:
                data = Data(report.optimizationReport(comparison: comparison).utf8)
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

    private func markUpdateChecked() {
        settings.lastUpdateCheckAt = Date()
        settingsStore.save(settings)
    }

    private func shouldPresentAutomaticUpdate(_ release: UpdateRelease) -> Bool {
        guard settings.automaticUpdateChecksEnabled else { return false }

        if settings.ignoredUpdateVersion == release.tagName {
            return false
        }

        if let reminder = settings.updateReminderAfter, reminder > Date() {
            return false
        }

        return true
    }

    private func presentUpdateAvailableAlert(_ release: UpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.tagName)"
        alert.informativeText = updateAlertText(for: release)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "打开 Release")
        alert.addButton(withTitle: "明天提醒")
        alert.addButton(withTitle: "忽略此版本")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { @MainActor in
                await downloadUpdate(release)
            }
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        } else if response == .alertThirdButtonReturn {
            remindUpdateLater(release)
        } else if response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1 {
            ignoreUpdate(release)
        }
    }

    private func presentNoUpdateAlert(_ release: UpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "当前版本：\(currentVersionText)\n最新版本：\(release.tagName)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func presentUpdateDownloadedAlert(_ downloaded: DownloadedUpdate) {
        let alert = NSAlert()
        alert.messageText = "更新包已下载"
        alert.informativeText = """
        已下载到：\(downloaded.fileURL.path)
        文件大小：\(downloaded.actualSizeText)

        安装步骤：
        1. 退出 NetEnvCheck。
        2. 解压下载的 NetEnvCheck.app.zip。
        3. 将新版 NetEnvCheck.app 拖入 Applications 并替换旧版。
        4. 重新打开 App。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func presentUpdateErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "更新检查失败"
        alert.informativeText = "\(message)\n\n可以稍后重试，或直接打开 GitHub Releases 页面下载。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func updateAlertText(for release: UpdateRelease) -> String {
        let notes = release.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(900)
        let releaseNotes = notes.isEmpty ? "此版本没有发布说明。" : String(notes)

        return """
        当前版本：\(currentVersionText)
        最新版本：\(release.tagName)
        安装包：\(release.assetName)（\(release.assetSizeText)）

        \(releaseNotes)
        """
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
