import Foundation
import Security

enum ProbeSourceID: String, CaseIterable, Codable, Identifiable, Sendable {
    case ipifyDual
    case ipifyIPv4
    case ipifyIPv6
    case ipwho
    case ipapi
    case ifconfig
    case ipinfo
    case dns
    case webRTC
    case httpHeaders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ipifyDual:
            "ipify 出口 IP"
        case .ipifyIPv4:
            "ipify IPv4"
        case .ipifyIPv6:
            "ipify IPv6"
        case .ipwho:
            "ipwho.is"
        case .ipapi:
            "ipapi.is"
        case .ifconfig:
            "ifconfig.co"
        case .ipinfo:
            "IPinfo Core"
        case .dns:
            "本机 DNS"
        case .webRTC:
            "WebRTC"
        case .httpHeaders:
            "HTTP 请求头"
        }
    }

    static var defaultEnabled: Set<ProbeSourceID> {
        Set(allCases)
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var defaultPreset: RiskPreset = .balanced
    var historyLimit: Int = 100
    var notificationsEnabled: Bool = true
    var automaticUpdateChecksEnabled: Bool = true
    var lastUpdateCheckAt: Date?
    var ignoredUpdateVersion: String?
    var updateReminderAfter: Date?
    var autoRefreshEnabled: Bool = false
    var autoRefreshIntervalMinutes: Int = 30
    var networkTimeoutSeconds: Int = 10
    var retryCount: Int = 1
    var cacheTTLSeconds: Int = 30
    var enabledSources: Set<ProbeSourceID> = ProbeSourceID.defaultEnabled

    enum CodingKeys: String, CodingKey {
        case defaultPreset
        case historyLimit
        case notificationsEnabled
        case automaticUpdateChecksEnabled
        case lastUpdateCheckAt
        case ignoredUpdateVersion
        case updateReminderAfter
        case autoRefreshEnabled
        case autoRefreshIntervalMinutes
        case networkTimeoutSeconds
        case retryCount
        case cacheTTLSeconds
        case enabledSources
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultPreset = try container.decodeIfPresent(RiskPreset.self, forKey: .defaultPreset) ?? .balanced
        historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 100
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        automaticUpdateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecksEnabled) ?? true
        lastUpdateCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckAt)
        ignoredUpdateVersion = try container.decodeIfPresent(String.self, forKey: .ignoredUpdateVersion)
        updateReminderAfter = try container.decodeIfPresent(Date.self, forKey: .updateReminderAfter)
        autoRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? false
        autoRefreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .autoRefreshIntervalMinutes) ?? 30
        networkTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .networkTimeoutSeconds) ?? 10
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 1
        cacheTTLSeconds = try container.decodeIfPresent(Int.self, forKey: .cacheTTLSeconds) ?? 30
        enabledSources = try container.decodeIfPresent(Set<ProbeSourceID>.self, forKey: .enabledSources) ?? ProbeSourceID.defaultEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultPreset, forKey: .defaultPreset)
        try container.encode(historyLimit, forKey: .historyLimit)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(automaticUpdateChecksEnabled, forKey: .automaticUpdateChecksEnabled)
        try container.encodeIfPresent(lastUpdateCheckAt, forKey: .lastUpdateCheckAt)
        try container.encodeIfPresent(ignoredUpdateVersion, forKey: .ignoredUpdateVersion)
        try container.encodeIfPresent(updateReminderAfter, forKey: .updateReminderAfter)
        try container.encode(autoRefreshEnabled, forKey: .autoRefreshEnabled)
        try container.encode(autoRefreshIntervalMinutes, forKey: .autoRefreshIntervalMinutes)
        try container.encode(networkTimeoutSeconds, forKey: .networkTimeoutSeconds)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(cacheTTLSeconds, forKey: .cacheTTLSeconds)
        try container.encode(enabledSources, forKey: .enabledSources)
    }

    func isEnabled(_ source: ProbeSourceID) -> Bool {
        enabledSources.contains(source)
    }

    var normalized: AppSettings {
        var copy = self
        copy.historyLimit = min(500, max(10, historyLimit))
        copy.autoRefreshIntervalMinutes = min(1440, max(5, autoRefreshIntervalMinutes))
        copy.networkTimeoutSeconds = min(30, max(3, networkTimeoutSeconds))
        copy.retryCount = min(3, max(0, retryCount))
        copy.cacheTTLSeconds = min(900, max(0, cacheTTLSeconds))
        return copy
    }
}

struct SettingsStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = SettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() -> AppSettings {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }

        return settings.normalized
    }

    func save(_ settings: AppSettings) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings.normalized)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NetEnvCheck settings save failed: \(error.localizedDescription)")
        }
    }

    static func defaultFileURL() -> URL {
        HistoryStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("settings.json")
    }
}

enum KeychainStore {
    private static let service = "local.codex.NetEnvCheck"
    private static let ipinfoAccount = "ipinfoToken"

    static func loadIPinfoToken() -> String {
        load(account: ipinfoAccount) ?? ""
    }

    static func saveIPinfoToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            delete(account: ipinfoAccount)
        } else {
            save(trimmed, account: ipinfoAccount)
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
