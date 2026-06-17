import Foundation
import SwiftUI

enum RiskBand: String, Codable, Sendable {
    case low
    case medium
    case high
    case unknown

    var title: String {
        switch self {
        case .low:
            "低风险 · 环境较一致"
        case .medium:
            "中风险 · 可用但建议优化"
        case .high:
            "高风险 · 建议更换环境"
        case .unknown:
            "检测中 · 等待结果"
        }
    }

    var message: String {
        switch self {
        case .low:
            "未发现明显异常，基础环境信号相对一致"
        case .medium:
            "检测到部分异常，建议核对代理、时区、DNS 或浏览器指纹"
        case .high:
            "检测到多项异常，结果可能影响登录、风控或服务可用性"
        case .unknown:
            "正在检查出口 IP、归属地、WebRTC、DNS、时区与语言设置"
        }
    }

    var foreground: Color {
        switch self {
        case .low:
            Color(red: 0.08, green: 0.36, blue: 0.23)
        case .medium:
            Color(red: 0.45, green: 0.23, blue: 0.04)
        case .high:
            Color(red: 0.56, green: 0.08, blue: 0.08)
        case .unknown:
            Color(red: 0.20, green: 0.24, blue: 0.31)
        }
    }

    var background: Color {
        switch self {
        case .low:
            Color(red: 0.88, green: 0.96, blue: 0.91)
        case .medium:
            Color(red: 0.98, green: 0.91, blue: 0.78)
        case .high:
            Color(red: 0.99, green: 0.88, blue: 0.86)
        case .unknown:
            Color(red: 0.91, green: 0.93, blue: 0.96)
        }
    }
}

enum RiskPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case balanced
    case strict
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            "均衡"
        case .strict:
            "严格"
        case .relaxed:
            "宽松"
        }
    }

    var detail: String {
        switch self {
        case .balanced:
            "适合日常登录前检查"
        case .strict:
            "对数据中心、泄露和不一致更敏感"
        case .relaxed:
            "减少误报，适合普通家庭/办公网络"
        }
    }

    var penaltyMultiplier: Double {
        switch self {
        case .balanced:
            1.0
        case .strict:
            1.2
        case .relaxed:
            0.75
        }
    }
}

enum ReportConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case unknown

    var title: String {
        switch self {
        case .high:
            "高可信"
        case .medium:
            "中可信"
        case .low:
            "低可信"
        case .unknown:
            "待确认"
        }
    }

    var message: String {
        switch self {
        case .high:
            "多个数据源返回结果且核心归属地一致"
        case .medium:
            "已有可用结果，但存在来源较少、部分失败或归属地冲突"
        case .low:
            "数据源返回不足，建议稍后重试或更换网络"
        case .unknown:
            "检测尚未完成"
        }
    }

    var foreground: Color {
        switch self {
        case .high:
            Color(red: 0.08, green: 0.36, blue: 0.23)
        case .medium:
            Color(red: 0.45, green: 0.23, blue: 0.04)
        case .low:
            Color(red: 0.56, green: 0.08, blue: 0.08)
        case .unknown:
            Color.secondary
        }
    }
}

struct ScoreImpact: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var points: Int
}

struct RiskScoreResult: Sendable {
    var score: Int
    var impacts: [ScoreImpact]
}

enum SourceState: String, Codable, Sendable {
    case success
    case warning
    case failure
    case disabled
}

struct SourceStatus: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(source)|\(url)" }
    var source: String
    var url: String
    var state: SourceState
    var durationMS: Int
    var errorMessage: String?

    var statusText: String {
        switch state {
        case .success:
            "成功 · \(durationMS) ms"
        case .warning:
            "提示 · \(durationMS) ms"
        case .failure:
            "失败 · \(durationMS) ms"
        case .disabled:
            "已关闭"
        }
    }
}

struct SourceObservation: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var source: String
    var ip: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var timezone: String?
    var asn: String?
    var organization: String?
    var isp: String?
    var ipType: String?

    init(
        source: String,
        ip: String?,
        country: String?,
        countryCode: String?,
        region: String?,
        city: String?,
        timezone: String?,
        asn: String?,
        organization: String?,
        isp: String?,
        ipType: String?
    ) {
        self.source = source
        self.ip = ip
        self.country = country
        self.countryCode = countryCode
        self.region = region
        self.city = city
        self.timezone = timezone
        self.asn = asn
        self.organization = organization
        self.isp = isp
        self.ipType = ipType
    }

    var locationText: String? {
        let parts = [city, region, country]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }

        if let countryCode, !countryCode.isEmpty {
            return countryCode.uppercased()
        }

        return nil
    }

    var asnText: String? {
        let normalizedASN = asn.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.uppercased().hasPrefix("AS") ? trimmed.uppercased() : "AS\(trimmed)"
        }

        let org = [organization, isp]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .first

        switch (normalizedASN, org) {
        case let (.some(asn), .some(org)):
            return "\(asn) · \(org)"
        case let (.some(asn), nil):
            return asn
        case let (nil, .some(org)):
            return org
        default:
            return nil
        }
    }
}

struct SecuritySummary: Codable, Sendable {
    var isDatacenter: Bool?
    var isProxy: Bool?
    var isVPN: Bool?
    var isTor: Bool?
    var isAbuser: Bool?
    var isMobile: Bool?
    var companyType: String?
    var companyName: String?
    var companyAbuserScore: String?
    var asnAbuserScore: String?

    mutating func merge(_ other: SecuritySummary) {
        isDatacenter = isDatacenter ?? other.isDatacenter
        isProxy = isProxy ?? other.isProxy
        isVPN = isVPN ?? other.isVPN
        isTor = isTor ?? other.isTor
        isAbuser = isAbuser ?? other.isAbuser
        isMobile = isMobile ?? other.isMobile
        companyType = companyType ?? other.companyType
        companyName = companyName ?? other.companyName
        companyAbuserScore = companyAbuserScore ?? other.companyAbuserScore
        asnAbuserScore = asnAbuserScore ?? other.asnAbuserScore
    }

    var proxyText: String {
        var hits: [String] = []

        if isProxy == true { hits.append("代理") }
        if isVPN == true { hits.append("VPN") }
        if isTor == true { hits.append("Tor") }

        if hits.isEmpty {
            if isDatacenter == true {
                return "未命中代理/VPN/Tor；但命中数据中心/托管网络"
            }
            return "未命中已知代理/VPN/Tor"
        }

        return "命中：" + hits.joined(separator: "、")
    }

    var ipKindText: String {
        var parts: [String] = []

        if isDatacenter == true { parts.append("数据中心") }
        if isMobile == true { parts.append("移动网络") }

        if let companyType, !companyType.isEmpty {
            parts.append(companyType)
        }

        return parts.isEmpty ? "未知" : Array(Set(parts)).sorted().joined(separator: " / ")
    }

    var abuseText: String {
        if isAbuser == true {
            return "命中滥用记录"
        }

        if let companyAbuserScore, !companyAbuserScore.isEmpty {
            return "公司评分 \(companyAbuserScore)"
        }

        if let asnAbuserScore, !asnAbuserScore.isEmpty {
            return "ASN 评分 \(asnAbuserScore)"
        }

        return "无记录"
    }
}

struct WebRTCCandidate: Codable, Hashable, Identifiable, Sendable {
    var address: String
    var type: String
    var transport: String

    var id: String {
        "\(address)|\(type)|\(transport)"
    }
}

struct BrowserEnvironment: Codable, Equatable, Sendable {
    var userAgent: String?
    var language: String?
    var languages: [String] = []
    var timezone: String?
    var httpHeaders: [String: String] = [:]
    var error: String?

    var acceptLanguage: String? {
        headerValue(named: "Accept-Language")
    }

    var displayText: String {
        let languageText = language ?? languages.first ?? "--"
        let timezoneText = timezone ?? "--"
        return "\(languageText) · \(timezoneText)"
    }

    func headerValue(named name: String) -> String? {
        httpHeaders.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

struct WebRTCProbePayload: Sendable {
    var supported: Bool
    var candidates: [WebRTCCandidate]
    var browser: BrowserEnvironment
    var error: String?
}

struct DNSResolverInfo: Codable, Equatable, Sendable {
    var nameservers: [String] = []
    var searchDomains: [String] = []
    var error: String?

    var publicResolvers: [String] {
        nameservers.filter { IPAddressClassifier.isPublic($0) }
    }

    var privateResolvers: [String] {
        nameservers.filter { !$0.isEmpty && !IPAddressClassifier.isPublic($0) }
    }

    var displayText: String {
        if let error, !error.isEmpty {
            return "读取失败：\(error)"
        }

        if nameservers.isEmpty {
            return "未读取到 DNS 服务器"
        }

        return nameservers.joined(separator: ", ")
    }
}

struct CheckReport: Codable, Sendable {
    var generatedAt = Date()
    var publicIP: String?
    var ipv4Address: String?
    var ipv6Address: String?
    var observations: [SourceObservation] = []
    var sourceStatuses: [SourceStatus] = []
    var security = SecuritySummary()
    var webRTCSupported: Bool?
    var webRTCCandidates: [WebRTCCandidate] = []
    var browser = BrowserEnvironment()
    var dns = DNSResolverInfo()
    var errors: [String] = []
    var localTimezone = TimeZone.current.identifier
    var preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
    var localRegion = Locale.current.region?.identifier
    var scoringPreset: RiskPreset = .balanced

    var primaryObservation: SourceObservation? {
        observations.first { $0.source == "ipwho.is" }
            ?? observations.first { $0.source == "ipapi.is" }
            ?? observations.first
    }

    var countryConflict: Bool {
        Set(observations.compactMap { $0.countryCode?.uppercased() }).count > 1
    }

    var sourceSuccessCount: Int {
        sourceStatuses.filter { $0.state == .success }.count
    }

    var confidence: ReportConfidence {
        guard publicIP != nil || !observations.isEmpty else {
            return .unknown
        }

        if sourceSuccessCount >= 3 && !countryConflict && errors.isEmpty {
            return .high
        }

        if sourceSuccessCount >= 1 {
            return .medium
        }

        return .low
    }

    var timezoneMismatch: Bool {
        guard let remoteTimezone = primaryObservation?.timezone, !remoteTimezone.isEmpty else {
            return false
        }
        return remoteTimezone != localTimezone
    }

    var browserTimezoneMismatch: Bool {
        guard
            let remoteTimezone = primaryObservation?.timezone,
            let browserTimezone = browser.timezone,
            !remoteTimezone.isEmpty,
            !browserTimezone.isEmpty
        else {
            return false
        }

        return browserTimezone != remoteTimezone
    }

    var languageRegion: String? {
        Self.regionCode(from: preferredLanguage) ?? localRegion
    }

    var browserLanguageRegion: String? {
        browser.language.flatMap(Self.regionCode(from:))
            ?? browser.languages.compactMap(Self.regionCode(from:)).first
    }

    var httpLanguageRegion: String? {
        guard let acceptLanguage = browser.acceptLanguage else { return nil }
        return acceptLanguage
            .split(separator: ",")
            .compactMap { item -> String? in
                let language = item.split(separator: ";").first.map(String.init)
                return language.flatMap(Self.regionCode(from:))
            }
            .first
    }

    var languageMismatch: Bool {
        guard
            let languageRegion = languageRegion?.uppercased(),
            let countryCode = primaryObservation?.countryCode?.uppercased(),
            !languageRegion.isEmpty,
            !countryCode.isEmpty
        else {
            return false
        }

        return languageRegion != countryCode
    }

    var browserLanguageMismatch: Bool {
        guard
            let browserLanguageRegion = browserLanguageRegion?.uppercased(),
            let countryCode = primaryObservation?.countryCode?.uppercased(),
            !browserLanguageRegion.isEmpty,
            !countryCode.isEmpty
        else {
            return false
        }

        return browserLanguageRegion != countryCode
    }

    var httpLanguageMismatch: Bool {
        guard
            let httpLanguageRegion = httpLanguageRegion?.uppercased(),
            let countryCode = primaryObservation?.countryCode?.uppercased(),
            !httpLanguageRegion.isEmpty,
            !countryCode.isEmpty
        else {
            return false
        }

        return httpLanguageRegion != countryCode
    }

    var publicWebRTCCandidates: [WebRTCCandidate] {
        webRTCCandidates.filter { IPAddressClassifier.isPublic($0.address) }
    }

    var mismatchedWebRTCIPs: [String] {
        guard let publicIP else { return [] }
        return Array(Set(publicWebRTCCandidates.map(\.address).filter { $0 != publicIP })).sorted()
    }

    var ipv6LeakSignal: Bool {
        guard let ipv4Address, let ipv6Address else { return false }
        return IPAddressClassifier.isPublic(ipv4Address) && IPAddressClassifier.isPublic(ipv6Address)
    }

    var dnsLeakSignal: Bool {
        let publicResolvers = dns.publicResolvers
        guard !publicResolvers.isEmpty else { return false }

        let wellKnownResolvers = Set([
            "1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4",
            "9.9.9.9", "149.112.112.112", "208.67.222.222", "208.67.220.220"
        ])

        return publicResolvers.contains { wellKnownResolvers.contains($0) }
    }

    var scoreResult: RiskScoreResult {
        RiskScoreEngine.result(for: self, preset: scoringPreset)
    }

    var riskScore: Int {
        scoreResult.score
    }

    var scoreBreakdown: [ScoreImpact] {
        scoreResult.impacts
    }

    var riskBand: RiskBand {
        guard publicIP != nil || !observations.isEmpty else {
            return .unknown
        }

        if riskScore >= 85 { return .low }
        if riskScore >= 60 { return .medium }
        return .high
    }

    var locationDisplay: String {
        let values = observations.compactMap { observation -> String? in
            guard let location = observation.locationText else { return nil }
            return "\(location)（\(observation.source)）"
        }

        return Self.unique(values).joined(separator: " / ").nilIfEmpty ?? "--"
    }

    var asnDisplay: String {
        let values = observations.compactMap { observation -> String? in
            guard let asn = observation.asnText else { return nil }
            return "\(asn)（\(observation.source)）"
        }

        return Self.unique(values).joined(separator: " / ").nilIfEmpty ?? "--"
    }

    var ipTypeDisplay: String {
        let base = primaryObservation?.ipType ?? "未知"
        let kind = security.ipKindText

        if kind == "未知" {
            return base
        }

        return "\(base) · \(kind)"
    }

    var ipVersionDisplay: String {
        switch (ipv4Address, ipv6Address) {
        case let (.some(ipv4), .some(ipv6)):
            return "IPv4 \(ipv4) / IPv6 \(ipv6)"
        case let (.some(ipv4), nil):
            return "IPv4 \(ipv4)"
        case let (nil, .some(ipv6)):
            return "IPv6 \(ipv6)"
        default:
            return publicIP.map { IPAddressClassifier.versionText(for: $0) + " \($0)" } ?? "--"
        }
    }

    var fraudDisplay: String {
        let scores = [security.companyAbuserScore, security.asnAbuserScore]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        if scores.isEmpty {
            return "\(riskScore) / 100（本地启发式评分）"
        }

        return scores.joined(separator: " / ")
    }

    var webRTCDisplay: String {
        if webRTCSupported == false {
            return "WebRTC 不可用或被禁用"
        }

        if !mismatchedWebRTCIPs.isEmpty {
            return "\(mismatchedWebRTCIPs.joined(separator: ", "))「不一致」"
        }

        let publicCandidates = publicWebRTCCandidates.map(\.address)

        if !publicCandidates.isEmpty {
            return "\(Array(Set(publicCandidates)).sorted().joined(separator: ", "))「一致」"
        }

        if webRTCSupported == nil {
            return "检测中"
        }

        return "未发现公网候选"
    }

    var timezoneDisplay: String {
        guard let remoteTimezone = primaryObservation?.timezone, !remoteTimezone.isEmpty else {
            return "\(localTimezone) = unknown"
        }

        return "\(localTimezone) \(timezoneMismatch ? "!=" : "=") \(remoteTimezone)"
    }

    var browserTimezoneDisplay: String {
        guard let timezone = browser.timezone, !timezone.isEmpty else {
            return "未读取到浏览器时区"
        }

        let remoteTimezone = primaryObservation?.timezone ?? "unknown"
        return "\(timezone) \(browserTimezoneMismatch ? "!=" : "=") \(remoteTimezone)"
    }

    var languageDisplay: String {
        let remoteCountry = primaryObservation?.countryCode?.uppercased() ?? "unknown country"
        let region = languageRegion?.uppercased() ?? "unknown region"
        let relation = languageMismatch ? "!=" : "="
        return "\(preferredLanguage) / \(region) \(relation) \(remoteCountry)"
    }

    var browserLanguageDisplay: String {
        let browserLanguage = browser.language ?? browser.languages.first ?? "--"
        let remoteCountry = primaryObservation?.countryCode?.uppercased() ?? "unknown country"
        let region = browserLanguageRegion?.uppercased() ?? "unknown region"
        let relation = browserLanguageMismatch ? "!=" : "="
        return "\(browserLanguage) / \(region) \(relation) \(remoteCountry)"
    }

    var httpHeaderDisplay: String {
        if let error = browser.error, !error.isEmpty {
            return "读取失败：\(error)"
        }

        if let acceptLanguage = browser.acceptLanguage, !acceptLanguage.isEmpty {
            return "Accept-Language: \(acceptLanguage)"
        }

        if browser.httpHeaders.isEmpty {
            return "未读取到 HTTP 头"
        }

        return "未发送 Accept-Language"
    }

    var issueSummary: [String] {
        var issues: [String] = []

        if countryConflict {
            issues.append("不同数据源给出的 IP 归属地不一致")
        }

        if security.isDatacenter == true {
            issues.append("出口 IP 位于数据中心或托管网络")
        }

        if security.isProxy == true || security.isVPN == true || security.isTor == true {
            issues.append("命中代理、VPN 或 Tor 识别")
        }

        if security.isAbuser == true {
            issues.append("命中滥用记录")
        }

        if !mismatchedWebRTCIPs.isEmpty {
            issues.append("WebRTC 暴露的公网 IP 与出口 IP 不一致")
        }

        if ipv6LeakSignal {
            issues.append("同时存在 IPv4 与 IPv6 出口，需确认代理是否覆盖 IPv6")
        }

        if dnsLeakSignal {
            issues.append("DNS 使用公共解析器，可能与出口环境不一致")
        }

        if timezoneMismatch {
            issues.append("系统时区与 IP 归属地时区不一致")
        }

        if browserTimezoneMismatch {
            issues.append("浏览器时区与 IP 归属地时区不一致")
        }

        if languageMismatch {
            issues.append("系统语言地区与 IP 归属地不一致")
        }

        if browserLanguageMismatch {
            issues.append("浏览器语言地区与 IP 归属地不一致")
        }

        if httpLanguageMismatch {
            issues.append("HTTP Accept-Language 与 IP 归属地不一致")
        }

        return issues
    }

    var remediationTips: [String] {
        var tips: [String] = []

        if security.isDatacenter == true {
            tips.append("如果目标服务更偏好住宅网络，可尝试更换为住宅或移动出口。")
        }

        if security.isProxy == true || security.isVPN == true || security.isTor == true {
            tips.append("代理/VPN/Tor 被公开情报源命中时，建议更换节点或降低代理特征。")
        }

        if !mismatchedWebRTCIPs.isEmpty {
            tips.append("浏览器 WebRTC 暴露了不同公网 IP，可在浏览器或代理工具中关闭 WebRTC 直连泄露。")
        }

        if ipv6LeakSignal {
            tips.append("确认代理工具是否接管 IPv6；不需要 IPv6 时可临时关闭系统 IPv6。")
        }

        if dnsLeakSignal {
            tips.append("DNS 使用公共解析器时，建议让 DNS 与代理出口保持一致，或使用代理工具提供的 DNS。")
        }

        if timezoneMismatch || browserTimezoneMismatch {
            tips.append("将系统/浏览器时区调整为与出口 IP 归属地一致。")
        }

        if languageMismatch || browserLanguageMismatch || httpLanguageMismatch {
            tips.append("将系统语言、浏览器语言和 Accept-Language 调整为与出口地区一致。")
        }

        if countryConflict {
            tips.append("多源归属地冲突时，建议等待 IP 情报库更新，或更换归属更稳定的出口。")
        }

        return Self.unique(tips)
    }

    var remediationPlans: [RemediationPlan] {
        RemediationEngine.plans(for: self)
    }

    var estimatedRemediationGain: Int {
        remediationPlans.map(\.estimatedScoreGain).reduce(0, +)
    }

    func remediationGuide() -> String {
        RemediationEngine.guide(for: self)
    }

    func plainTextReport() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        return """
        网络环境检测报告
        时间：\(formatter.string(from: generatedAt))
        评分：\(riskScore) / 100
        风险：\(riskBand.title)
        可信度：\(confidence.title)
        评分预设：\(scoringPreset.title)

        出口 IP：\(publicIP ?? "--")
        IP 协议：\(ipVersionDisplay)
        归属地：\(locationDisplay)
        ASN：\(asnDisplay)
        IP 类型：\(ipTypeDisplay)
        代理识别：\(security.proxyText)
        欺诈/滥用：\(fraudDisplay)
        近期滥用：\(security.abuseText)
        WebRTC：\(webRTCDisplay)
        DNS：\(dns.displayText)
        系统时区：\(timezoneDisplay)
        浏览器时区：\(browserTimezoneDisplay)
        系统语言：\(languageDisplay)
        浏览器语言：\(browserLanguageDisplay)
        HTTP 头：\(httpHeaderDisplay)

        扣分明细：
        \(scoreBreakdown.isEmpty ? "无扣分项" : scoreBreakdown.map { "- \($0.title)：\($0.points)（\($0.detail)）" }.joined(separator: "\n"))

        异常发现：
        \(issueSummary.isEmpty ? "未发现明显异常" : issueSummary.map { "- \($0)" }.joined(separator: "\n"))

        修复建议：
        \(remediationTips.isEmpty ? "暂无建议" : remediationTips.map { "- \($0)" }.joined(separator: "\n"))

        数据源状态：
        \(sourceStatuses.isEmpty ? "无数据源状态" : sourceStatuses.map { "- \($0.source)：\($0.statusText)\($0.errorMessage.map { "，\($0)" } ?? "")" }.joined(separator: "\n"))

        备注：检测结果仅供参考，不保证与 Claude 官方判定一致。
        """
    }

    func markdownReport() -> String {
        """
        # 网络环境检测报告

        - 时间：\(DateFormatter.reportFormatter.string(from: generatedAt))
        - 评分：\(riskScore) / 100
        - 风险：\(riskBand.title)
        - 可信度：\(confidence.title)
        - 评分预设：\(scoringPreset.title)

        ## 基础信息

        | 项目 | 结果 |
        | --- | --- |
        | 出口 IP | \(publicIP ?? "--") |
        | IP 协议 | \(ipVersionDisplay) |
        | 归属地 | \(locationDisplay) |
        | ASN | \(asnDisplay) |
        | IP 类型 | \(ipTypeDisplay) |
        | 代理识别 | \(security.proxyText) |
        | DNS | \(dns.displayText) |
        | WebRTC | \(webRTCDisplay) |
        | 系统时区 | \(timezoneDisplay) |
        | 浏览器时区 | \(browserTimezoneDisplay) |
        | 系统语言 | \(languageDisplay) |
        | 浏览器语言 | \(browserLanguageDisplay) |
        | HTTP 头 | \(httpHeaderDisplay) |

        ## 扣分明细

        \(scoreBreakdown.isEmpty ? "无扣分项" : scoreBreakdown.map { "- **\($0.title)**：\($0.points)；\($0.detail)" }.joined(separator: "\n"))

        ## 异常发现

        \(issueSummary.isEmpty ? "未发现明显异常" : issueSummary.map { "- \($0)" }.joined(separator: "\n"))

        ## 修复建议

        \(remediationTips.isEmpty ? "暂无建议" : remediationTips.map { "- \($0)" }.joined(separator: "\n"))

        ## 数据源状态

        \(sourceStatuses.isEmpty ? "无数据源状态" : sourceStatuses.map { "- \($0.source)：\($0.statusText)\($0.errorMessage.map { "；\($0)" } ?? "")" }.joined(separator: "\n"))

        > 检测结果仅供参考，不保证与 Claude 官方判定一致。
        """
    }

    func htmlReport() -> String {
        let rows: [(String, String)] = [
            ("出口 IP", publicIP ?? "--"),
            ("IP 协议", ipVersionDisplay),
            ("归属地", locationDisplay),
            ("ASN", asnDisplay),
            ("IP 类型", ipTypeDisplay),
            ("代理识别", security.proxyText),
            ("DNS", dns.displayText),
            ("WebRTC", webRTCDisplay),
            ("系统时区", timezoneDisplay),
            ("浏览器时区", browserTimezoneDisplay),
            ("系统语言", languageDisplay),
            ("浏览器语言", browserLanguageDisplay),
            ("HTTP 头", httpHeaderDisplay)
        ]

        let issueHTML = issueSummary.isEmpty
            ? "<li>未发现明显异常</li>"
            : issueSummary.map { "<li>\(Self.escapeHTML($0))</li>" }.joined()

        let scoreHTML = scoreBreakdown.isEmpty
            ? "<li>无扣分项</li>"
            : scoreBreakdown.map { "<li><strong>\(Self.escapeHTML($0.title))</strong>：\($0.points)；\(Self.escapeHTML($0.detail))</li>" }.joined()

        let sourceHTML = sourceStatuses.isEmpty
            ? "<li>无数据源状态</li>"
            : sourceStatuses.map { status in
                "<li><strong>\(Self.escapeHTML(status.source))</strong>：\(Self.escapeHTML(status.statusText))\(status.errorMessage.map { "；\(Self.escapeHTML($0))" } ?? "")</li>"
            }.joined()

        let tipsHTML = remediationTips.isEmpty
            ? "<li>暂无建议</li>"
            : remediationTips.map { "<li>\(Self.escapeHTML($0))</li>" }.joined()

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>NetEnvCheck Report</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; margin: 32px; color: #28231f; background: #fbf7f1; }
            main { max-width: 860px; margin: auto; background: white; border: 1px solid #eadfd2; border-radius: 12px; padding: 28px; }
            h1 { margin: 0 0 8px; }
            .score { font-size: 42px; font-weight: 700; color: #af4a34; margin: 18px 0; }
            .meta { color: #746b63; }
            table { width: 100%; border-collapse: collapse; margin-top: 20px; }
            th, td { border-bottom: 1px solid #eee4da; padding: 10px 0; text-align: left; vertical-align: top; }
            th { width: 120px; color: #8a8178; }
            section { margin-top: 24px; }
            li { margin: 7px 0; }
          </style>
        </head>
        <body>
        <main>
          <h1>网络环境检测报告</h1>
          <div class="meta">\(Self.escapeHTML(DateFormatter.reportFormatter.string(from: generatedAt))) · \(Self.escapeHTML(scoringPreset.title)) · \(Self.escapeHTML(confidence.title))</div>
          <div class="score">\(riskScore) / 100</div>
          <p><strong>\(Self.escapeHTML(riskBand.title))</strong>：\(Self.escapeHTML(riskBand.message))</p>
          <table>
            <tbody>
              \(rows.map { "<tr><th>\(Self.escapeHTML($0.0))</th><td>\(Self.escapeHTML($0.1))</td></tr>" }.joined(separator: "\n"))
            </tbody>
          </table>
          <section><h2>扣分明细</h2><ul>\(scoreHTML)</ul></section>
          <section><h2>异常发现</h2><ul>\(issueHTML)</ul></section>
          <section><h2>修复建议</h2><ul>\(tipsHTML)</ul></section>
          <section><h2>数据源状态</h2><ul>\(sourceHTML)</ul></section>
          <p class="meta">检测结果仅供参考，不保证与 Claude 或任何服务的官方风控判定一致。</p>
        </main>
        </body>
        </html>
        """
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static func regionCode(from identifier: String) -> String? {
        let separators = CharacterSet(charactersIn: "-_")
        let parts = identifier.components(separatedBy: separators)

        return parts.last.flatMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count == 2, trimmed.allSatisfy(\.isLetter) else {
                return nil
            }
            return trimmed.uppercased()
        }
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum RiskScoreEngine {
    static func result(for report: CheckReport, preset: RiskPreset) -> RiskScoreResult {
        var impacts: [ScoreImpact] = []

        func add(_ id: String, _ title: String, _ detail: String, basePenalty: Int) {
            let adjusted = max(1, Int((Double(basePenalty) * preset.penaltyMultiplier).rounded()))
            impacts.append(ScoreImpact(id: id, title: title, detail: detail, points: -adjusted))
        }

        if report.publicIP == nil {
            add("public-ip", "未获取出口 IP", "核心检测源未能返回公网 IP", basePenalty: 45)
        }

        if report.countryConflict {
            add("country-conflict", "归属地冲突", "不同数据源给出的国家/地区不一致", basePenalty: 18)
        }

        if report.security.isDatacenter == true {
            add("datacenter", "数据中心网络", "出口 IP 位于托管、云服务或机房网络", basePenalty: 22)
        }

        if report.security.isProxy == true {
            add("proxy", "代理识别", "公开情报源命中代理信号", basePenalty: 35)
        }

        if report.security.isVPN == true {
            add("vpn", "VPN 识别", "公开情报源命中 VPN 信号", basePenalty: 35)
        }

        if report.security.isTor == true {
            add("tor", "Tor 识别", "公开情报源命中 Tor 出口节点", basePenalty: 45)
        }

        if report.security.isAbuser == true {
            add("abuse", "滥用记录", "公开情报源命中近期或历史滥用信号", basePenalty: 22)
        }

        if !report.mismatchedWebRTCIPs.isEmpty {
            add("webrtc", "WebRTC IP 不一致", "浏览器候选公网 IP 与出口 IP 不一致", basePenalty: 30)
        }

        if report.ipv6LeakSignal {
            add("ipv6", "IPv6 额外出口", "同时存在 IPv4 与 IPv6 出口，需确认代理是否覆盖 IPv6", basePenalty: 12)
        }

        if report.dnsLeakSignal {
            add("dns", "DNS 公共解析器", "系统 DNS 使用常见公共解析器，可能形成环境不一致信号", basePenalty: 8)
        }

        if report.timezoneMismatch {
            add("system-timezone", "系统时区不一致", "系统时区与 IP 归属地时区不一致", basePenalty: 14)
        }

        if report.browserTimezoneMismatch {
            add("browser-timezone", "浏览器时区不一致", "WebView 暴露时区与 IP 归属地时区不一致", basePenalty: 10)
        }

        if report.languageMismatch {
            add("system-language", "系统语言不一致", "系统语言地区与 IP 归属地不一致", basePenalty: 8)
        }

        if report.browserLanguageMismatch {
            add("browser-language", "浏览器语言不一致", "浏览器语言地区与 IP 归属地不一致", basePenalty: 8)
        }

        if report.httpLanguageMismatch {
            add("http-language", "HTTP 语言头不一致", "Accept-Language 与 IP 归属地不一致", basePenalty: 5)
        }

        let score = max(0, min(100, 100 + impacts.map(\.points).reduce(0, +)))
        return RiskScoreResult(score: score, impacts: impacts)
    }
}

enum IPAddressClassifier {
    static func isPublic(_ address: String) -> Bool {
        let lowercased = address.lowercased()

        if lowercased.isEmpty || lowercased.hasSuffix(".local") {
            return false
        }

        if let octets = ipv4Octets(lowercased) {
            return isPublicIPv4(octets)
        }

        if lowercased.contains(":") {
            return isPublicIPv6(lowercased)
        }

        return false
    }

    static func versionText(for address: String) -> String {
        if ipv4Octets(address) != nil {
            return "IPv4"
        }

        if address.contains(":") {
            return "IPv6"
        }

        return "IP"
    }

    private static func ipv4Octets(_ address: String) -> [Int]? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }

        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }

        return octets
    }

    private static func isPublicIPv4(_ octets: [Int]) -> Bool {
        let first = octets[0]
        let second = octets[1]

        if first == 0 || first == 10 || first == 127 { return false }
        if first == 100 && (64...127).contains(second) { return false }
        if first == 169 && second == 254 { return false }
        if first == 172 && (16...31).contains(second) { return false }
        if first == 192 && second == 168 { return false }
        if first >= 224 { return false }

        return true
    }

    private static func isPublicIPv6(_ address: String) -> Bool {
        if address == "::1" { return false }
        if address.hasPrefix("fe80:") { return false }
        if address.hasPrefix("fc") || address.hasPrefix("fd") { return false }
        return true
    }
}

private extension DateFormatter {
    static let reportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
