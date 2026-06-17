import AppKit
import Darwin
import SwiftUI

@main
struct NetEnvCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTestRunner.run())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 820, minHeight: 820)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    SettingsWindowController.shared.show(appState: appState)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        statusBarController = StatusBarController()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        configureMenu()
        updateStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusItem),
            name: .netEnvCheckReportDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusItem),
            name: .netEnvCheckRefreshStateDidChange,
            object: nil
        )
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 NetEnvCheck", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重新检测", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "复制报告", action: #selector(copyReport), keyEquivalent: "c"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "导出 Markdown", action: #selector(exportMarkdown), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出 JSON", action: #selector(exportJSON), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出 HTML", action: #selector(exportHTML), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出优化报告", action: #selector(exportOptimization), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "检查更新", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "隐私说明", action: #selector(showPrivacy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "关于 NetEnvCheck", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        menu.items.last?.target = NSApp
        statusItem.menu = menu
    }

    @objc private func updateStatusItem() {
        let appState = AppState.shared
        let report = appState.report
        let symbolName: String

        if appState.isRefreshing || appState.webRTCPending {
            symbolName = "arrow.triangle.2.circlepath"
        } else {
            switch report.riskBand {
            case .low:
                symbolName = "checkmark.shield"
            case .medium:
                symbolName = "exclamationmark.shield"
            case .high:
                symbolName = "xmark.shield"
            case .unknown:
                symbolName = "network"
            }
        }

        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "NetEnvCheck")
        statusItem.button?.title = report.publicIP == nil ? "" : " \(report.riskScore)"
        statusItem.button?.toolTip = "\(report.riskBand.title) · \(report.publicIP ?? "--") · \(DateFormatter.statusFormatter.string(from: report.generatedAt))"
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "NetEnvCheck" || $0.contentViewController is NSHostingController<ContentView> }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
        }
    }

    @objc private func refresh() {
        Task { @MainActor in
            await AppState.shared.refresh()
        }
    }

    @objc private func copyReport() {
        AppState.shared.copyReport()
    }

    @objc private func exportMarkdown() {
        AppState.shared.exportCurrentReport(as: .markdown)
    }

    @objc private func exportJSON() {
        AppState.shared.exportCurrentReport(as: .json)
    }

    @objc private func exportHTML() {
        AppState.shared.exportCurrentReport(as: .html)
    }

    @objc private func exportOptimization() {
        AppState.shared.exportCurrentReport(as: .optimization)
    }

    @objc private func checkForUpdates() {
        Task { @MainActor in
            await AppState.shared.checkForUpdates(userInitiated: true)
        }
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show(appState: AppState.shared)
    }

    @objc private func showPrivacy() {
        let alert = NSAlert()
        alert.messageText = "隐私说明"
        alert.informativeText = "NetEnvCheck 会向公开 IP/HTTP 检测接口请求当前网络环境信息，并把历史检测结果保存在本机 Application Support/NetEnvCheck/history.json。不会上传本地历史记录。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }
}

private extension DateFormatter {
    static let statusFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
