import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tokenDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置")
                    .font(.system(size: 22, weight: .semibold))

                Spacer()

                Button("清空历史", role: .destructive) {
                    appState.clearHistory()
                }
            }

            Form {
                Section("检测") {
                    Picker("默认评分预设", selection: settingsBinding(\.defaultPreset)) {
                        ForEach(RiskPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }

                    Toggle("启用通知", isOn: settingsBinding(\.notificationsEnabled))
                    Toggle("自动重新检测", isOn: settingsBinding(\.autoRefreshEnabled))

                    Stepper(
                        "自动检测间隔：\(appState.settings.autoRefreshIntervalMinutes) 分钟",
                        value: settingsBinding(\.autoRefreshIntervalMinutes),
                        in: 5...1440,
                        step: 5
                    )
                }

                Section("网络") {
                    Stepper(
                        "超时：\(appState.settings.networkTimeoutSeconds) 秒",
                        value: settingsBinding(\.networkTimeoutSeconds),
                        in: 3...30
                    )
                    Stepper(
                        "失败重试：\(appState.settings.retryCount) 次",
                        value: settingsBinding(\.retryCount),
                        in: 0...3
                    )
                    Stepper(
                        "短时缓存：\(appState.settings.cacheTTLSeconds) 秒",
                        value: settingsBinding(\.cacheTTLSeconds),
                        in: 0...900,
                        step: 15
                    )
                }

                Section("历史") {
                    Stepper(
                        "保留记录：\(appState.settings.historyLimit) 条",
                        value: settingsBinding(\.historyLimit),
                        in: 10...500,
                        step: 10
                    )
                }

                Section("IPinfo Core") {
                    SecureField("Token", text: $tokenDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("保存 Token") {
                            appState.updateIPinfoToken(tokenDraft)
                        }

                        Button("清空 Token") {
                            tokenDraft = ""
                            appState.updateIPinfoToken("")
                        }

                        Spacer()
                    }
                }

                Section("数据源") {
                    ForEach(ProbeSourceID.allCases) { source in
                        Toggle(source.title, isOn: sourceBinding(source))
                    }
                }
            }
            .formStyle(.grouped)
            .hiddenScrollIndicators()
        }
        .padding(24)
        .frame(width: 560, height: 680)
        .onAppear {
            tokenDraft = appState.ipinfoToken
        }
    }

    private func settingsBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding {
            appState.settings[keyPath: keyPath]
        } set: { value in
            appState.updateSettings { settings in
                settings[keyPath: keyPath] = value
            }
        }
    }

    private func sourceBinding(_ source: ProbeSourceID) -> Binding<Bool> {
        Binding {
            appState.settings.enabledSources.contains(source)
        } set: { isEnabled in
            appState.updateSettings { settings in
                if isEnabled {
                    settings.enabledSources.insert(source)
                } else {
                    settings.enabledSources.remove(source)
                }
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            AppMark()
                .frame(width: 74, height: 74)

            Text("NetEnvCheck")
                .font(.system(size: 22, weight: .semibold))

            Text("Version 1.2.0")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("本地网络环境风险检测工具。结果仅供参考，不保证与任何服务的官方风控判定一致。")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link("联系作者：https://t.me/xiemecoin", destination: URL(string: "https://t.me/xiemecoin")!)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(28)
        .frame(width: 360)
    }
}
