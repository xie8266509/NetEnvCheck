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
                        restoreAction: appState.restore
                    )
                }
                .frame(maxWidth: 1080)
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            WebRTCProbeView(refreshToken: appState.refreshToken) { payload in
                appState.applyWebRTC(payload)
            }
            .frame(width: 2, height: 2)
            .opacity(0.01)
            .allowsHitTesting(false)

            HiddenScrollIndicatorConfigurator()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .onAppear {
            appState.startIfNeeded()
        }
    }
}

private struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleConfiguration(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfiguration(from: nsView)
    }

    private func scheduleConfiguration(from view: NSView) {
        DispatchQueue.main.async {
            configureScrollViews(near: view)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            configureScrollViews(near: view)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            configureScrollViews(near: view)
        }
    }

    private func configureScrollViews(near view: NSView) {
        if let root = view.window?.contentView {
            configureScrollViews(in: root)
            return
        }

        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView ?? candidate.enclosingScrollView {
                configure(scrollView)
            }

            current = candidate.superview
        }
    }

    private func configureScrollViews(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            configure(scrollView)
        }

        view.subviews.forEach(configureScrollViews(in:))
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.postsBoundsChangedNotifications = true
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

private struct AppMark: View {
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
    var restoreAction: (SavedReport) -> Void

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
                RiskDetailView(report: report)
            case .sources:
                SourceDetailView(report: report)
            case .history:
                HistoryDetailView(comparison: comparison, history: history, restoreAction: restoreAction)
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
            DetailRow(label: "系统时区", value: report.timezoneDisplay, state: report.timezoneMismatch ? .warning : .neutral)
            DetailRow(label: "浏览器时区", value: report.browserTimezoneDisplay, state: report.browserTimezoneMismatch ? .warning : .neutral)
            DetailRow(label: "系统语言", value: report.languageDisplay, state: report.languageMismatch ? .warning : .neutral)
            DetailRow(label: "浏览器语言", value: report.browserLanguageDisplay, state: report.browserLanguageMismatch ? .warning : .neutral)
            DetailRow(label: "HTTP 语言头", value: report.httpHeaderDisplay, state: report.httpLanguageMismatch ? .warning : .neutral)
        }
    }
}

private struct RiskDetailView: View {
    var report: CheckReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SummaryStat(title: "可信度", value: report.confidence.title, color: report.confidence.foreground)
                SummaryStat(title: "评分预设", value: report.scoringPreset.title, color: AppTheme.clay)
                SummaryStat(title: "扣分项", value: "\(report.scoreBreakdown.count)", color: report.scoreBreakdown.isEmpty ? AppTheme.moss : AppTheme.amber)
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
}

private struct SourceDetailView: View {
    var report: CheckReport

    var body: some View {
        VStack(spacing: 0) {
            if report.sourceStatuses.isEmpty {
                DetailRow(label: "状态", value: "等待检测")
            } else {
                ForEach(report.sourceStatuses) { status in
                    DetailRow(
                        label: status.source,
                        value: status.errorMessage.map { "\(status.statusText) · \($0)" } ?? status.statusText,
                        state: status.state == .success ? .neutral : .warning
                    )
                }
            }
        }
    }
}

private struct HistoryDetailView: View {
    var comparison: ReportComparison?
    var history: [SavedReport]
    var restoreAction: (SavedReport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                }

                if history.isEmpty {
                    Text("完成一次检测后会自动保存")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(history.prefix(8))) { item in
                            Button {
                                restoreAction(item)
                            } label: {
                                HistoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
