import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDetail: DetailTab = .environment

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppTheme.background
                .ignoresSafeArea()
                .overlay(AppTheme.warmWash.opacity(0.28).ignoresSafeArea())

            ScrollView {
                VStack(spacing: 20) {
                    AppHeader(
                        selectedPreset: $appState.selectedPreset,
                        isRefreshing: appState.isRefreshing || appState.webRTCPending,
                        lastActionMessage: appState.lastActionMessage,
                        refreshAction: {
                            Task { await appState.refresh() }
                        },
                        copyAction: appState.copyReport,
                        exportMarkdownAction: {
                            appState.exportCurrentReport(as: .markdown)
                        },
                        exportJSONAction: {
                            appState.exportCurrentReport(as: .json)
                        },
                        exportHTMLAction: {
                            appState.exportCurrentReport(as: .html)
                        },
                        exportOptimizationAction: {
                            appState.exportCurrentReport(as: .optimization)
                        }
                    )

                    DashboardView(
                        report: appState.report,
                        isRefreshing: appState.isRefreshing,
                        webRTCPending: appState.webRTCPending
                    )

                    IssueSummaryView(report: appState.report)

                    DetailTabsView(
                        selectedDetail: $selectedDetail,
                        report: appState.report,
                        comparison: appState.comparison,
                        history: appState.history,
                        retryAction: {
                            Task { await appState.refresh() }
                        },
                        restoreAction: appState.restore,
                        deleteAction: appState.deleteHistoryItem,
                        clearAction: appState.clearHistory
                    )
                }
                .frame(maxWidth: 1080)
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .hiddenScrollIndicators()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        AppTheme.background.opacity(0),
                        AppTheme.background.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .allowsHitTesting(false)
            }

            WebRTCProbeView(refreshToken: appState.refreshToken) { payload in
                appState.applyWebRTC(payload)
            }
            .frame(width: 2, height: 2)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
        .onAppear {
            appState.startIfNeeded()
        }
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case environment
    case risk
    case sources
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .environment:
            "环境"
        case .risk:
            "风险"
        case .sources:
            "数据源"
        case .history:
            "历史"
        }
    }
}

private enum AppTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let warmWash = Color(red: 0.98, green: 0.94, blue: 0.88)
    static let clay = Color(red: 0.69, green: 0.29, blue: 0.20)
    static let claySoft = Color(red: 0.98, green: 0.87, blue: 0.80)
    static let ink = Color(red: 0.17, green: 0.15, blue: 0.13)
    static let moss = Color(red: 0.08, green: 0.36, blue: 0.27)
    static let amber = Color(red: 0.70, green: 0.38, blue: 0.08)
    static let line = Color(nsColor: .separatorColor)
}

private struct AppHeader: View {
    @Binding var selectedPreset: RiskPreset
    var isRefreshing: Bool
    var lastActionMessage: String?
    var refreshAction: () -> Void
    var copyAction: () -> Void
    var exportMarkdownAction: () -> Void
    var exportJSONAction: () -> Void
    var exportHTMLAction: () -> Void
    var exportOptimizationAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            AppMark()

            VStack(alignment: .leading, spacing: 5) {
                Text("NetEnvCheck")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)

                Text("网络环境风险检测")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                Picker("评分预设", selection: $selectedPreset) {
                    ForEach(RiskPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
                .help(selectedPreset.detail)

                Button(action: copyAction) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                    Menu {
                        Button("Markdown", action: exportMarkdownAction)
                        Button("JSON", action: exportJSONAction)
                        Button("HTML", action: exportHTMLAction)
                        Button("优化报告", action: exportOptimizationAction)
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.down")
                    }
                .menuStyle(.button)

                Button(action: refreshAction) {
                    Label(isRefreshing ? "检测中" : "重新检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
            }

            if let lastActionMessage {
                Text(lastActionMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .trailing)
            }
        }
    }
}

struct AppMark: View {
    var body: some View {
        Group {
            if let image = AppIconLoader.image() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                AppMarkFallback()
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
    }
}

private enum AppIconLoader {
    static func image() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon-source", withExtension: "png") {
            return NSImage(contentsOf: url)
        }

        let developmentURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon-source.png")

        if let image = NSImage(contentsOf: developmentURL) {
            return image
        }

        return NSImage(named: "AppIcon")
    }
}

private struct AppMarkFallback: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.warmWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.clay.opacity(0.20), lineWidth: 1)
                )

            Circle()
                .stroke(Color.white.opacity(0.42), lineWidth: 9)
                .frame(width: 30, height: 30)

            Circle()
                .trim(from: 0.08, to: 0.80)
                .stroke(AppTheme.clay, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-120))
                .frame(width: 28, height: 28)

            Path { path in
                path.move(to: CGPoint(x: 22, y: 22))
                path.addLine(to: CGPoint(x: 29, y: 15))
            }
            .stroke(AppTheme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Circle()
                .fill(AppTheme.ink)
                .frame(width: 7, height: 7)

            Circle()
                .fill(AppTheme.moss)
                .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 2))
                .frame(width: 10, height: 10)
                .offset(x: 9, y: -9)
        }
    }
}

private struct DashboardView: View {
    var report: CheckReport
    var isRefreshing: Bool
    var webRTCPending: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScoreHeroCard(report: report, isRefreshing: isRefreshing, webRTCPending: webRTCPending)
                .frame(width: 350)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                MetricTile(title: "出口 IP", value: report.publicIP ?? "--", symbol: "network", state: .neutral)
                MetricTile(title: "归属地", value: report.primaryObservation?.locationText ?? "--", symbol: "mappin.and.ellipse", state: report.countryConflict ? .warning : .neutral)
                MetricTile(title: "ASN", value: report.primaryObservation?.asnText ?? "--", symbol: "point.3.connected.trianglepath.dotted", state: .neutral)
                MetricTile(title: "WebRTC", value: report.webRTCDisplay, symbol: "dot.radiowaves.left.and.right", state: report.mismatchedWebRTCIPs.isEmpty ? .neutral : .danger)
                MetricTile(title: "DNS", value: report.dns.displayText, symbol: "server.rack", state: report.dnsLeakSignal ? .warning : .neutral)
                MetricTile(title: "浏览器", value: report.browser.displayText, symbol: "globe", state: report.browserTimezoneMismatch || report.browserLanguageMismatch ? .warning : .neutral)
            }
        }
    }
}

private struct ScoreHeroCard: View {
    var report: CheckReport
    var isRefreshing: Bool
    var webRTCPending: Bool

    var body: some View {
        HStack(spacing: 22) {
            ScoreRing(score: report.riskScore, band: report.riskBand)
                .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 12) {
                StatusPill(title: report.riskBand.title, band: report.riskBand)

                Text(statusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    CompactBadge(
                        title: report.confidence.title,
                        symbol: "checkmark.seal",
                        color: report.confidence.foreground
                    )
                    CompactBadge(
                        title: report.scoringPreset.title,
                        symbol: "slider.horizontal.3",
                        color: AppTheme.clay
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.clay.opacity(0.18), lineWidth: 1)
        )
    }

    private var statusMessage: String {
        if isRefreshing {
            return "正在检测出口 IP、归属地、ASN、IPv6 与 DNS"
        }

        if webRTCPending {
            return "正在等待 WebRTC、浏览器指纹与 HTTP 头"
        }

        return report.riskBand.message
    }
}

private struct ScoreRing: View {
    var score: Int
    var band: RiskBand

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.line.opacity(0.45), lineWidth: 10)

            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 33, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                Text("/ 100")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ringColor: Color {
        switch band {
        case .low:
            AppTheme.moss
        case .medium:
            AppTheme.amber
        case .high:
            AppTheme.clay
        case .unknown:
            Color.secondary
        }
    }
}

private struct StatusPill: View {
    var title: String
    var band: RiskBand

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private var symbolName: String {
        switch band {
        case .low:
            "checkmark.shield"
        case .medium:
            "exclamationmark.shield"
        case .high:
            "xmark.shield"
        case .unknown:
            "hourglass"
        }
    }

    private var color: Color {
        switch band {
        case .low:
            AppTheme.moss
        case .medium:
            AppTheme.amber
        case .high:
            AppTheme.clay
        case .unknown:
            Color.secondary
        }
    }
}

private enum MetricState {
    case neutral
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral:
            Color.secondary
        case .warning:
            AppTheme.amber
        case .danger:
            AppTheme.clay
        }
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String
    var state: MetricState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(state.color)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
        }
        .padding(14)
        .frame(minHeight: 94)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.elevated.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(state.color.opacity(state == .neutral ? 0.14 : 0.38), lineWidth: 1)
        )
    }
}

private struct CompactBadge: View {
    var title: String
    var symbol: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.10))
        )
    }
}

private struct IssueSummaryView: View {
    var report: CheckReport

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.issueSummary.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(report.issueSummary.isEmpty ? AppTheme.moss : AppTheme.clay)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 8) {
                Text(report.issueSummary.isEmpty ? "未发现明显异常" : "关键发现")
                    .font(.system(size: 14, weight: .semibold))

                FlowLayout(spacing: 8, rowSpacing: 8) {
                    if report.issueSummary.isEmpty {
                        IssueChip(text: "核心信号相对一致", color: AppTheme.moss)
                    } else {
                        ForEach(report.issueSummary.prefix(5), id: \.self) { issue in
                            IssueChip(text: issue, color: AppTheme.clay)
                        }

                        if report.issueSummary.count > 5 {
                            IssueChip(text: "另有 \(report.issueSummary.count - 5) 项", color: AppTheme.amber)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.line.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct IssueChip: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.10))
            )
    }
}

private struct DetailTabsView: View {
    @Binding var selectedDetail: DetailTab
    var report: CheckReport
    var comparison: ReportComparison?
    var history: [SavedReport]
    var retryAction: () -> Void
    var restoreAction: (SavedReport) -> Void
    var deleteAction: (SavedReport) -> Void
    var clearAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Picker("详情", selection: $selectedDetail) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 330)

                Spacer()

                Text("检测结果仅供参考，不保证与 Claude 官方判定一致")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            switch selectedDetail {
            case .environment:
                EnvironmentDetailView(report: report)
            case .risk:
                RiskDetailView(report: report, comparison: comparison)
            case .sources:
                SourceDetailView(report: report, retryAction: retryAction)
            case .history:
                HistoryDetailView(
                    comparison: comparison,
                    history: history,
                    restoreAction: restoreAction,
                    deleteAction: deleteAction,
                    clearAction: clearAction
                )
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.line.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct EnvironmentDetailView: View {
    var report: CheckReport

    var body: some View {
        VStack(spacing: 0) {
            DetailRow(label: "IP 地址", value: report.publicIP ?? "--")
            DetailRow(label: "IP 协议", value: report.ipVersionDisplay, state: report.ipv6LeakSignal ? .warning : .neutral)
            DetailRow(label: "归属地", value: report.locationDisplay, state: report.countryConflict ? .warning : .neutral)
            DetailRow(label: "ASN", value: report.asnDisplay)
            DetailRow(label: "IP 类型", value: report.ipTypeDisplay, state: report.security.isDatacenter == true ? .warning : .neutral)
            DetailRow(label: "代理识别", value: report.security.proxyText, state: report.security.isProxy == true || report.security.isVPN == true || report.security.isTor == true || report.security.isDatacenter == true ? .danger : .neutral)
            DetailRow(label: "WebRTC IP", value: report.webRTCDisplay, state: report.mismatchedWebRTCIPs.isEmpty ? .neutral : .danger)
            DetailRow(label: "DNS", value: report.dns.displayText, state: report.dnsLeakSignal ? .warning : .neutral)
            DetailRow(label: "DNS 外显", value: report.dns.observedResolverDisplayText, state: .neutral)
            DetailRow(label: "系统代理", value: report.systemProxy?.displayText ?? "--", state: report.systemProxySignal ? .warning : .neutral)
            DetailRow(label: "网络接口", value: report.networkInterfaces?.displayText ?? "--", state: report.tunnelInterfaceSignal ? .warning : .neutral)
            DetailRow(label: "系统时区", value: report.timezoneDisplay, state: report.timezoneMismatch ? .warning : .neutral)
            DetailRow(label: "浏览器时区", value: report.browserTimezoneDisplay, state: report.browserTimezoneMismatch ? .warning : .neutral)
            DetailRow(label: "系统语言", value: report.languageDisplay, state: report.languageMismatch ? .warning : .neutral)
            DetailRow(label: "浏览器语言", value: report.browserLanguageDisplay, state: report.browserLanguageMismatch ? .warning : .neutral)
            DetailRow(label: "HTTP 语言头", value: report.httpHeaderDisplay, state: report.httpLanguageMismatch ? .warning : .neutral)
        }
    }
}

private struct RiskDetailView: View {
    @EnvironmentObject private var appState: AppState
    var report: CheckReport
    var comparison: ReportComparison?
    @State private var handledPlanIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SummaryStat(title: "可信度", value: report.confidence.title, color: report.confidence.foreground)
                SummaryStat(title: "评分预设", value: report.scoringPreset.title, color: AppTheme.clay)
                SummaryStat(title: "扣分项", value: "\(report.scoreBreakdown.count)", color: report.scoreBreakdown.isEmpty ? AppTheme.moss : AppTheme.amber)
                SummaryStat(
                    title: "预计改善",
                    value: report.remediationPlans.isEmpty ? "--" : "+\(report.estimatedRemediationGain)",
                    color: report.remediationPlans.isEmpty ? Color.secondary : AppTheme.moss
                )
            }

            VStack(spacing: 0) {
                if report.scoreBreakdown.isEmpty {
                    DetailRow(label: "当前评分", value: "无扣分项")
                } else {
                    ForEach(report.scoreBreakdown) { impact in
                        DetailRow(label: impact.title, value: "\(impact.points) · \(impact.detail)", state: .danger)
                    }
                }
            }

            RemediationCenterView(
                report: report,
                comparison: comparison,
                handledPlanIDs: handledPlanIDs,
                copyAllAction: appState.copyRemediationGuide,
                refreshAction: {
                    Task { await appState.refresh() }
                },
                markHandledAction: { plan in
                    handledPlanIDs.insert(plan.id)
                    appState.showMessage("已标记处理")
                },
                actionHandler: perform
            )

            if !report.errors.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("接口提示")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(report.errors, id: \.self) { error in
                        FindingInlineRow(text: error, symbol: "exclamationmark.triangle", color: AppTheme.amber)
                    }
                }
            }
        }
    }

    private func perform(_ action: RemediationAction) {
        switch action.kind {
        case .openSettings(let destination):
            appState.openSystemSettings(destination)
        case .copyCommand(let command):
            appState.copyText(command, message: "命令已复制")
        case .copyGuide(let guide):
            appState.copyText(guide, message: "指南已复制")
        case .copyText(let text):
            appState.copyText(text, message: "内容已复制")
        case .refresh:
            Task { await appState.refresh() }
        case .markHandled:
            appState.showMessage("已标记处理")
        }
    }
}

private struct RemediationCenterView: View {
    var report: CheckReport
    var comparison: ReportComparison?
    var handledPlanIDs: Set<String>
    var copyAllAction: () -> Void
    var refreshAction: () -> Void
    var markHandledAction: (RemediationPlan) -> Void
    var actionHandler: (RemediationAction) -> Void
    @State private var expandedPlanIDs: Set<String> = []

    private var plans: [RemediationPlan] {
        report.remediationPlans
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("修复中心")
                        .font(.system(size: 14, weight: .semibold))

                    Text(plans.isEmpty ? "当前没有可执行的修复项" : "按预计改善优先级排序，建议处理后立即复测")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    copyAllAction()
                } label: {
                    Label("复制全部方案", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(plans.isEmpty)

                Button {
                    refreshAction()
                } label: {
                    Label("应用后重新检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            RemediationProgressView(comparison: comparison)

            if plans.isEmpty {
                FindingInlineRow(text: "当前信号较一致，无需修复。保持当前网络、时区、语言和 DNS 设置即可。", symbol: "checkmark.seal", color: AppTheme.moss)
            } else {
                VStack(spacing: 0) {
                    ForEach(plans) { plan in
                        RemediationPlanRow(
                            plan: plan,
                            isExpanded: expandedPlanIDs.contains(plan.id),
                            isHandled: handledPlanIDs.contains(plan.id),
                            toggleExpandedAction: {
                                if expandedPlanIDs.contains(plan.id) {
                                    expandedPlanIDs.remove(plan.id)
                                } else {
                                    expandedPlanIDs.insert(plan.id)
                                }
                            },
                            markHandledAction: {
                                markHandledAction(plan)
                            },
                            actionHandler: actionHandler
                        )

                        if plan.id != plans.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear {
            if expandedPlanIDs.isEmpty, let first = plans.first {
                expandedPlanIDs.insert(first.id)
            }
        }
    }
}

private struct RemediationProgressView: View {
    var comparison: ReportComparison?

    var body: some View {
        if let comparison {
            HStack(spacing: 12) {
                RemediationMetric(
                    title: "评分变化",
                    value: scoreDeltaText(comparison),
                    color: scoreDelta(comparison) >= 0 ? AppTheme.moss : AppTheme.clay
                )
                RemediationMetric(
                    title: "已改善项",
                    value: "\(resolvedImpactIDs(comparison).count)",
                    color: AppTheme.moss
                )
                RemediationMetric(
                    title: "新增风险",
                    value: "\(newImpactIDs(comparison).count)",
                    color: newImpactIDs(comparison).isEmpty ? Color.secondary : AppTheme.amber
                )
            }

            let resolved = resolvedImpactTitles(comparison)
            if !resolved.isEmpty {
                FindingInlineRow(
                    text: "已改善：\(resolved.prefix(3).joined(separator: "、"))",
                    symbol: "arrow.up.right.circle",
                    color: AppTheme.moss
                )
            }
        } else {
            Text("完成优化后重新检测，这里会显示评分变化、已改善项和新增风险。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func scoreDelta(_ comparison: ReportComparison) -> Int {
        comparison.current.riskScore - comparison.previous.riskScore
    }

    private func scoreDeltaText(_ comparison: ReportComparison) -> String {
        let delta = scoreDelta(comparison)
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }

    private func resolvedImpactIDs(_ comparison: ReportComparison) -> Set<String> {
        let previous = Set(comparison.previous.scoreBreakdown.map(\.id))
        let current = Set(comparison.current.scoreBreakdown.map(\.id))
        return previous.subtracting(current)
    }

    private func newImpactIDs(_ comparison: ReportComparison) -> Set<String> {
        let previous = Set(comparison.previous.scoreBreakdown.map(\.id))
        let current = Set(comparison.current.scoreBreakdown.map(\.id))
        return current.subtracting(previous)
    }

    private func resolvedImpactTitles(_ comparison: ReportComparison) -> [String] {
        let resolved = resolvedImpactIDs(comparison)
        return comparison.previous.scoreBreakdown
            .filter { resolved.contains($0.id) }
            .map(\.title)
    }
}

private struct RemediationMetric: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.elevated.opacity(0.70))
        )
    }
}

private struct RemediationPlanRow: View {
    var plan: RemediationPlan
    var isExpanded: Bool
    var isHandled: Bool
    var toggleExpandedAction: () -> Void
    var markHandledAction: () -> Void
    var actionHandler: (RemediationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.category.symbolName)
                    .foregroundStyle(categoryColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button {
                            toggleExpandedAction()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(plan.title)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)

                        if isHandled {
                            Label("已处理", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.moss)
                        }
                    }

                    Text(plan.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(nil)

                    if isExpanded {
                        Text(plan.whyItMatters)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("+\(plan.estimatedScoreGain)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.moss)

                    Text("预计改善")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 72, alignment: .trailing)
            }

            FlowLayout(spacing: 8, rowSpacing: 8) {
                RemediationTag(text: plan.category.title, symbol: plan.category.symbolName, color: categoryColor)
                RemediationTag(text: plan.difficulty.title, symbol: "speedometer", color: AppTheme.amber)
                RemediationTag(text: plan.safety.title, symbol: "lock.shield", color: safetyColor)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(categoryColor)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(categoryColor.opacity(0.10))
                                )

                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        }
                    }
                }

                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(plan.actions) { action in
                        RemediationActionButton(action: action) {
                            actionHandler(action)
                        }
                    }

                    Button {
                        markHandledAction()
                    } label: {
                        Label("标记已处理", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isHandled)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var categoryColor: Color {
        switch plan.category {
        case .network:
            Color.accentColor
        case .browser:
            AppTheme.amber
        case .system:
            AppTheme.moss
        case .identity:
            AppTheme.clay
        case .data:
            Color.secondary
        }
    }

    private var safetyColor: Color {
        switch plan.safety {
        case .safe:
            AppTheme.moss
        case .manual:
            AppTheme.amber
        case .admin:
            AppTheme.clay
        }
    }
}

private struct RemediationTag: View {
    var text: String
    var symbol: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.10))
        )
    }
}

private struct RemediationActionButton: View {
    var action: RemediationAction
    var perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Label(action.title, systemImage: action.systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(action.safety.title)
    }
}

private struct SourceDetailView: View {
    var report: CheckReport
    var retryAction: () -> Void

    private var retryableCount: Int {
        report.sourceStatuses.filter { $0.state == .failure || $0.state == .warning }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("数据源状态")
                        .font(.system(size: 13, weight: .semibold))

                    Text(retryableCount == 0 ? "所有启用的数据源状态正常" : "\(retryableCount) 个数据源需要关注")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    retryAction()
                } label: {
                    Label("重试检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(retryableCount == 0)
            }

            if report.sourceStatuses.isEmpty {
                DetailRow(label: "状态", value: "等待检测")
            } else {
                VStack(spacing: 0) {
                    ForEach(report.sourceStatuses) { status in
                        DetailRow(
                            label: status.source,
                            value: status.displayErrorMessage.map { "\(status.statusText) · \($0)" } ?? status.statusText,
                            state: status.state == .failure ? .warning : .neutral
                        )
                    }
                }
            }
        }
    }
}

private struct HistoryDetailView: View {
    var comparison: ReportComparison?
    var history: [SavedReport]
    var restoreAction: (SavedReport) -> Void
    var deleteAction: (SavedReport) -> Void
    var clearAction: () -> Void
    @State private var query = ""

    private var filteredHistory: [SavedReport] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return history }

        return history.filter { item in
            [
                item.report.publicIP,
                item.report.locationDisplay,
                item.report.asnDisplay,
                item.report.riskBand.title
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if history.count >= 2 {
                ScoreTrendView(history: history)
            }

            if let comparison, !comparison.changes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本次变化")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(comparison.changes) { change in
                            ComparisonRow(change: change)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("历史记录")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(history.count) 条")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button("清空", role: .destructive, action: clearAction)
                        .font(.system(size: 12))
                }

                TextField("搜索 IP、归属地、ASN 或风险等级", text: $query)
                    .textFieldStyle(.roundedBorder)

                if history.isEmpty {
                    Text("完成一次检测后会自动保存")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if filteredHistory.isEmpty {
                    Text("没有匹配的历史记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredHistory.prefix(20))) { item in
                            HStack(spacing: 10) {
                                Button {
                                    restoreAction(item)
                                } label: {
                                    HistoryRow(item: item)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    deleteAction(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("删除这条记录")
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ScoreTrendView: View {
    var history: [SavedReport]

    private var points: [SavedReport] {
        Array(history.prefix(24).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("评分趋势")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let size = proxy.size
                let values = points.map { CGFloat($0.report.riskScore) }
                let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
                let path = trendPath(values: values, size: size, step: step)

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.elevated.opacity(0.72))

                    Path { path in
                        for index in 0...4 {
                            let y = size.height * CGFloat(index) / 4
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(AppTheme.line.opacity(0.35), lineWidth: 1)

                    path
                        .stroke(AppTheme.clay, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        Circle()
                            .fill(value >= 85 ? AppTheme.moss : (value >= 60 ? AppTheme.amber : AppTheme.clay))
                            .frame(width: 6, height: 6)
                            .position(x: CGFloat(index) * step, y: size.height - (value / 100 * size.height))
                    }
                }
            }
            .frame(height: 120)
        }
    }

    private func trendPath(values: [CGFloat], size: CGSize, step: CGFloat) -> Path {
        Path { path in
            guard let first = values.first else { return }
            path.move(to: CGPoint(x: 0, y: size.height - (first / 100 * size.height)))

            for item in values.dropFirst().enumerated() {
                let x = CGFloat(item.offset + 1) * step
                let y = size.height - (item.element / 100 * size.height)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
}

private struct DetailRow: View {
    var label: String
    var value: String
    var state: MetricState = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.color.opacity(state == .neutral ? 0.25 : 1))
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 128, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(state == .neutral ? Color.primary : state.color)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct SummaryStat: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.elevated.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct FindingInlineRow: View {
    var text: String
    var symbol: String
    var color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
    }
}

private struct ComparisonRow: View {
    var change: ComparisonItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(change.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(change.previous)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(change.isImportant ? AppTheme.amber : Color.secondary)

            Text(change.current)
                .font(.system(size: 13, weight: change.isImportant ? .medium : .regular))
                .foregroundStyle(change.isImportant ? Color.primary : Color.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct HistoryRow: View {
    var item: SavedReport

    var body: some View {
        HStack(spacing: 14) {
            ScoreMiniBadge(score: item.report.riskScore, band: item.report.riskBand)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.report.publicIP ?? "--")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                Text(DateFormatter.historyFormatter.string(from: item.savedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.report.riskBand.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(item.report.riskBand.foreground)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ScoreMiniBadge: View {
    var score: Int
    var band: RiskBand

    var body: some View {
        Text("\(score)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 38, height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private var color: Color {
        switch band {
        case .low:
            AppTheme.moss
        case .medium:
            AppTheme.amber
        case .high:
            AppTheme.clay
        case .unknown:
            Color.secondary
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(for proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [FlowRow] = []
        var current = FlowRow()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width

            if nextWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }

            current.items.append(FlowItem(subview: subview, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct FlowItem {
        var subview: LayoutSubview
        var size: CGSize
    }

    private struct FlowRow {
        var items: [FlowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}

private extension DateFormatter {
    static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
