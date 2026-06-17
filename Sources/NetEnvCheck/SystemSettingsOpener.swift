import AppKit
import Foundation

enum SystemSettingsDestination: String, Sendable {
    case dateTime
    case languageRegion
    case network
    case vpn

    var title: String {
        switch self {
        case .dateTime:
            "日期与时间"
        case .languageRegion:
            "语言与地区"
        case .network:
            "网络"
        case .vpn:
            "VPN/网络"
        }
    }

    var urlCandidates: [String] {
        switch self {
        case .dateTime:
            [
                "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.datetime"
            ]
        case .languageRegion:
            [
                "x-apple.systempreferences:com.apple.Localization-Settings.extension",
                "x-apple.systempreferences:com.apple.Localization"
            ]
        case .network:
            [
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network"
            ]
        case .vpn:
            [
                "x-apple.systempreferences:com.apple.Network-Settings.extension?VPN",
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network"
            ]
        }
    }
}

enum SystemSettingsOpener {
    @MainActor
    @discardableResult
    static func open(_ destination: SystemSettingsDestination) -> Bool {
        for candidate in destination.urlCandidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        guard let fallback = URL(string: "x-apple.systempreferences:") else {
            return false
        }
        return NSWorkspace.shared.open(fallback)
    }
}
