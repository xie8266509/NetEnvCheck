import Foundation

struct ProbeService: Sendable {
    func run(
        preset: RiskPreset = .balanced,
        settings: AppSettings = AppSettings(),
        ipinfoToken: String = ""
    ) async -> CheckReport {
        var report = CheckReport()
        report.scoringPreset = preset

        async let ipifyDualResult = settings.isEnabled(.ipifyDual)
            ? captureSource(source: "ipify dual", sourceID: .ipifyDual, url: "https://api64.ipify.org?format=json", settings: settings) {
                try await fetchJSON(IpifyResponse.self, from: "https://api64.ipify.org?format=json", settings: settings)
            }
            : disabledSource(IpifyResponse.self, source: "ipify dual", sourceID: .ipifyDual, url: "https://api64.ipify.org?format=json")

        async let ipifyIPv4Result = settings.isEnabled(.ipifyIPv4)
            ? captureSource(source: "ipify IPv4", sourceID: .ipifyIPv4, url: "https://api.ipify.org?format=json", settings: settings) {
                try await fetchJSON(IpifyResponse.self, from: "https://api.ipify.org?format=json", settings: settings)
            }
            : disabledSource(IpifyResponse.self, source: "ipify IPv4", sourceID: .ipifyIPv4, url: "https://api.ipify.org?format=json")

        async let ipifyIPv6Result = settings.isEnabled(.ipifyIPv6)
            ? captureSource(source: "ipify IPv6", sourceID: .ipifyIPv6, url: "https://api6.ipify.org?format=json", settings: settings, failureState: .warning) {
                try await fetchJSON(IpifyResponse.self, from: "https://api6.ipify.org?format=json", settings: settings)
            }
            : disabledSource(IpifyResponse.self, source: "ipify IPv6", sourceID: .ipifyIPv6, url: "https://api6.ipify.org?format=json")

        async let ipwhoResult = settings.isEnabled(.ipwho)
            ? captureSource(source: "ipwho.is", sourceID: .ipwho, url: "https://ipwho.is/", settings: settings) {
                try await fetchJSON(IPWhoResponse.self, from: "https://ipwho.is/", settings: settings)
            }
            : disabledSource(IPWhoResponse.self, source: "ipwho.is", sourceID: .ipwho, url: "https://ipwho.is/")

        async let ipapiIsResult = settings.isEnabled(.ipapi)
            ? captureSource(source: "ipapi.is", sourceID: .ipapi, url: "https://api.ipapi.is/", settings: settings) {
                try await fetchJSON(IPAPIISResponse.self, from: "https://api.ipapi.is/", settings: settings)
            }
            : disabledSource(IPAPIISResponse.self, source: "ipapi.is", sourceID: .ipapi, url: "https://api.ipapi.is/")

        async let ifconfigResult = settings.isEnabled(.ifconfig)
            ? captureSource(source: "ifconfig.co", sourceID: .ifconfig, url: "https://ifconfig.co/json", settings: settings) {
                try await fetchJSON(IfconfigResponse.self, from: "https://ifconfig.co/json", settings: settings)
            }
            : disabledSource(IfconfigResponse.self, source: "ifconfig.co", sourceID: .ifconfig, url: "https://ifconfig.co/json")

        async let dnsResult = settings.isEnabled(.dns)
            ? DNSResolverProbe().run()
            : DNSResolverProbeResult(
                info: DNSResolverInfo(),
                statuses: [SourceStatus(source: "local DNS", url: "scutil --dns", state: .disabled, durationMS: 0, errorMessage: nil)]
            )
        async let proxyResult = SystemProxyProbe().run()
        async let interfaceResult = NetworkInterfaceProbe().run()

        let ipifyDual = await ipifyDualResult
        let ipifyIPv4 = await ipifyIPv4Result
        let ipifyIPv6 = await ipifyIPv6Result
        let ipwho = await ipwhoResult
        let ipapiIs = await ipapiIsResult
        let ifconfig = await ifconfigResult
        let dns = await dnsResult
        let proxy = await proxyResult
        let interfaces = await interfaceResult

        [
            ipifyDual.status,
            ipifyIPv4.status,
            ipifyIPv6.status,
            ipwho.status,
            ipapiIs.status,
            ifconfig.status
        ].forEach { report.sourceStatuses.append($0) }
        dns.statuses.forEach { report.sourceStatuses.append($0) }
        report.sourceStatuses.append(proxy.status)
        report.sourceStatuses.append(interfaces.status)

        switch ipifyDual.result {
        case let .success(response):
            report.publicIP = response.ip
        case let .failure(error):
            appendError(error, from: ipifyDual.status, to: &report)
        }

        switch ipifyIPv4.result {
        case let .success(response):
            if let ip = response.ip, IPAddressClassifier.versionText(for: ip) == "IPv4" {
                report.ipv4Address = ip
                if report.publicIP == nil {
                    report.publicIP = ip
                }
            }
        case let .failure(error):
            appendError(error, from: ipifyIPv4.status, to: &report)
        }

        switch ipifyIPv6.result {
        case let .success(response):
            guard let ip = response.ip, IPAddressClassifier.versionText(for: ip) == "IPv6" else { break }
            report.ipv6Address = ip
            if report.publicIP == nil {
                report.publicIP = ip
            }
        case .failure:
            break
        }

        switch ipwho.result {
        case let .success(response):
            report.observations.append(response.observation)
            if report.publicIP == nil {
                report.publicIP = response.ip
            }
        case let .failure(error):
            appendError(error, from: ipwho.status, to: &report)
        }

        switch ipapiIs.result {
        case let .success(response):
            report.observations.append(response.observation)
            report.security = response.security
            if report.publicIP == nil {
                report.publicIP = response.ip
            }
        case let .failure(error):
            appendError(error, from: ipapiIs.status, to: &report)
        }

        switch ifconfig.result {
        case let .success(response):
            report.observations.append(response.observation)
            if report.publicIP == nil {
                report.publicIP = response.ip
            }
        case let .failure(error):
            appendError(error, from: ifconfig.status, to: &report)
        }

        report.dns = dns.info
        if let error = dns.info.error, !error.isEmpty {
            report.errors.append("DNS：\(FriendlyErrorMessage.text(error, source: "DNS"))")
        }
        report.systemProxy = proxy.info
        report.networkInterfaces = interfaces.snapshot

        await applyCommercialIntel(to: &report, settings: settings, token: ipinfoToken)

        return report
    }

    private func applyCommercialIntel(to report: inout CheckReport, settings: AppSettings, token: String) async {
        guard settings.isEnabled(.ipinfo) else {
            report.sourceStatuses.append(
                SourceStatus(source: "IPinfo Core", url: "https://api.ipinfo.io/lookup", state: .disabled, durationMS: 0, errorMessage: nil)
            )
            return
        }

        let token = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CommercialIntelConfig.load().ipinfoToken
            : token

        guard let token, !token.isEmpty else {
            return
        }

        let target = report.publicIP ?? "me"
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        let url = "https://api.ipinfo.io/lookup/\(target)?token=\(encodedToken)"
        let displayURL = "https://api.ipinfo.io/lookup/\(target)"

        let ipinfo = await captureSource(
            source: "IPinfo Core",
            sourceID: .ipinfo,
            url: url,
            displayURL: displayURL,
            settings: settings
        ) {
            try await fetchJSON(IPInfoCoreResponse.self, from: url, settings: settings)
        }

        report.sourceStatuses.append(ipinfo.status)

        switch ipinfo.result {
        case let .success(response):
            report.observations.append(response.observation)
            report.security.merge(response.security)
            if report.publicIP == nil {
                report.publicIP = response.ip
            }
        case let .failure(error):
            appendError(error, from: ipinfo.status, to: &report)
        }
    }

    private func appendError(_ error: Error, from status: SourceStatus, to report: inout CheckReport) {
        guard status.state != .disabled else { return }
        report.errors.append("\(status.source)：\(FriendlyErrorMessage.text(error.localizedDescription, source: status.source))")
    }

    private func captureSource<T: Decodable & Sendable>(
        source: String,
        sourceID: ProbeSourceID,
        url: String,
        displayURL: String? = nil,
        settings: AppSettings,
        failureState: SourceState = .failure,
        _ operation: @Sendable @escaping () async throws -> T
    ) async -> ProbeSourceResult<T> {
        let startedAt = Date()

        do {
            let value = try await retry(settings.retryCount, operation)
            return ProbeSourceResult(
                result: .success(value),
                status: SourceStatus(
                    source: source,
                    url: displayURL ?? url,
                    state: .success,
                    durationMS: Self.durationMS(since: startedAt),
                    errorMessage: nil
                )
            )
        } catch {
            return ProbeSourceResult(
                result: .failure(error),
                status: SourceStatus(
                    source: source,
                    url: displayURL ?? url,
                    state: failureState,
                    durationMS: Self.durationMS(since: startedAt),
                    errorMessage: error.localizedDescription
                )
            )
        }
    }

    private func fetchJSON<T: Decodable & Sendable>(
        _ type: T.Type,
        from urlString: String,
        settings: AppSettings
    ) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw ProbeError.invalidURL(urlString)
        }

        if settings.cacheTTLSeconds > 0, let cached = await ProbeResponseCache.shared.get(urlString, as: T.self, ttl: settings.cacheTTLSeconds) {
            return cached
        }

        var request = URLRequest(url: url, timeoutInterval: TimeInterval(settings.networkTimeoutSeconds))
        request.setValue("NetEnvCheck/1.1 (+local macOS app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(220), encoding: .utf8) ?? ""
            throw ProbeError.badStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(type, from: data)
        await ProbeResponseCache.shared.set(urlString, data: data)
        return decoded
    }

    private func retry<T>(
        _ count: Int,
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0...count {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < count {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
                }
            }
        }

        throw lastError ?? ProbeError.invalidResponse
    }

    private func disabledSource<T: Sendable>(
        _ type: T.Type,
        source: String,
        sourceID: ProbeSourceID,
        url: String
    ) -> ProbeSourceResult<T> {
        ProbeSourceResult(
            result: .failure(ProbeError.sourceDisabled(sourceID.title)),
            status: SourceStatus(source: source, url: url, state: .disabled, durationMS: 0, errorMessage: nil)
        )
    }

    private static func durationMS(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}

private struct ProbeSourceResult<T: Sendable>: Sendable {
    var result: Result<T, Error>
    var status: SourceStatus
}

private actor ProbeResponseCache {
    static let shared = ProbeResponseCache()

    private struct Entry {
        var data: Data
        var savedAt: Date
    }

    private var entries: [String: Entry] = [:]

    func get<T: Decodable & Sendable>(_ key: String, as type: T.Type, ttl: Int) -> T? {
        guard
            let entry = entries[key],
            Date().timeIntervalSince(entry.savedAt) <= TimeInterval(ttl)
        else {
            entries[key] = nil
            return nil
        }

        return try? JSONDecoder().decode(type, from: entry.data)
    }

    func set(_ key: String, data: Data) {
        entries[key] = Entry(data: data, savedAt: Date())
    }
}

private struct DNSResolverProbe: Sendable {
    func run() async -> DNSResolverProbeResult {
        let startedAt = Date()

        do {
            let output = try runScutilDNS()
            var info = parse(output)
            let localStatus = SourceStatus(
                source: "local DNS",
                url: "scutil --dns",
                state: info.nameservers.isEmpty ? .warning : .success,
                durationMS: durationMS(since: startedAt),
                errorMessage: info.nameservers.isEmpty ? "未读取到 DNS 服务器" : nil
            )

            let leakStartedAt = Date()
            let leakResult = try? runDNSLeakProbe()
            info.observedResolverIPs = leakResult
            let leakStatus = SourceStatus(
                source: "DNS leak probe",
                url: "dig TXT o-o.myaddr.l.google.com",
                state: (leakResult?.isEmpty ?? true) ? .warning : .success,
                durationMS: durationMS(since: leakStartedAt),
                errorMessage: (leakResult?.isEmpty ?? true) ? "未读取到外显解析器" : nil
            )

            return DNSResolverProbeResult(info: info, statuses: [localStatus, leakStatus])
        } catch {
            let info = DNSResolverInfo(error: error.localizedDescription)
            let status = SourceStatus(
                source: "local DNS",
                url: "scutil --dns",
                state: .warning,
                durationMS: durationMS(since: startedAt),
                errorMessage: error.localizedDescription
            )
            return DNSResolverProbeResult(info: info, statuses: [status])
        }
    }

    private func runScutilDNS() throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--dns"]
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProbeError.commandFailed("scutil --dns", message ?? "exit \(process.terminationStatus)")
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func runDNSLeakProbe() throws -> [String] {
        guard FileManager.default.fileExists(atPath: "/usr/bin/dig") else {
            return []
        }

        let output = try CommandRunner.run(
            executablePath: "/usr/bin/dig",
            arguments: ["+time=3", "+tries=1", "+short", "TXT", "o-o.myaddr.l.google.com"]
        )

        let regex = try NSRegularExpression(pattern: #"(?:(?:\d{1,3}\.){3}\d{1,3})"#)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return CheckReport.unique(regex.matches(in: output, range: range).compactMap { match in
            Range(match.range, in: output).map { String(output[$0]) }
        })
    }

    private func parse(_ output: String) -> DNSResolverInfo {
        var nameservers: [String] = []
        var searchDomains: [String] = []

        output.components(separatedBy: .newlines).forEach { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("nameserver["), let value = valueAfterColon(in: trimmed) {
                nameservers.append(value)
            }

            if trimmed.hasPrefix("search domain["), let value = valueAfterColon(in: trimmed) {
                searchDomains.append(value)
            }
        }

        return DNSResolverInfo(
            nameservers: CheckReport.unique(nameservers),
            searchDomains: CheckReport.unique(searchDomains),
            error: nil
        )
    }

    private func valueAfterColon(in line: String) -> String? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func durationMS(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}

private struct DNSResolverProbeResult: Sendable {
    var info: DNSResolverInfo
    var statuses: [SourceStatus]
}

private struct SystemProxyProbeResult: Sendable {
    var info: SystemProxyInfo
    var status: SourceStatus
}

private struct SystemProxyProbe: Sendable {
    func run() async -> SystemProxyProbeResult {
        let startedAt = Date()

        do {
            let output = try CommandRunner.run(executablePath: "/usr/sbin/scutil", arguments: ["--proxy"])
            let info = parse(output)
            return SystemProxyProbeResult(
                info: info,
                status: SourceStatus(
                    source: "system proxy",
                    url: "scutil --proxy",
                    state: .success,
                    durationMS: durationMS(since: startedAt),
                    errorMessage: nil
                )
            )
        } catch {
            return SystemProxyProbeResult(
                info: SystemProxyInfo(),
                status: SourceStatus(
                    source: "system proxy",
                    url: "scutil --proxy",
                    state: .warning,
                    durationMS: durationMS(since: startedAt),
                    errorMessage: error.localizedDescription
                )
            )
        }
    }

    private func parse(_ output: String) -> SystemProxyInfo {
        var info = SystemProxyInfo()
        info.httpEnabled = output.contains("HTTPEnable : 1")
        info.httpsEnabled = output.contains("HTTPSEnable : 1")
        info.socksEnabled = output.contains("SOCKSEnable : 1")
        info.pacEnabled = output.contains("ProxyAutoConfigEnable : 1")
        info.proxyAutoDiscoveryEnabled = output.contains("ProxyAutoDiscoveryEnable : 1")
        return info
    }

    private func durationMS(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}

private struct NetworkInterfaceProbeResult: Sendable {
    var snapshot: NetworkInterfaceSnapshot
    var status: SourceStatus
}

private struct NetworkInterfaceProbe: Sendable {
    func run() async -> NetworkInterfaceProbeResult {
        let startedAt = Date()

        do {
            let output = try CommandRunner.run(executablePath: "/sbin/ifconfig", arguments: [])
            let snapshot = parse(output)
            return NetworkInterfaceProbeResult(
                snapshot: snapshot,
                status: SourceStatus(
                    source: "network interfaces",
                    url: "ifconfig",
                    state: .success,
                    durationMS: durationMS(since: startedAt),
                    errorMessage: nil
                )
            )
        } catch {
            return NetworkInterfaceProbeResult(
                snapshot: NetworkInterfaceSnapshot(),
                status: SourceStatus(
                    source: "network interfaces",
                    url: "ifconfig",
                    state: .warning,
                    durationMS: durationMS(since: startedAt),
                    errorMessage: error.localizedDescription
                )
            )
        }
    }

    private func parse(_ output: String) -> NetworkInterfaceSnapshot {
        let blocks = output.components(separatedBy: "\n\n")
        var active: [String] = []
        var tunnels: [String] = []

        for block in blocks {
            guard let firstLine = block.split(separator: "\n").first else { continue }
            let name = firstLine.split(separator: ":").first.map(String.init) ?? ""
            guard !name.isEmpty else { continue }

            let isActive = block.contains("status: active") || block.contains("UP,")
            let isTunnel = name.hasPrefix("utun") || name.hasPrefix("tun") || name.hasPrefix("tap") || name.hasPrefix("ppp") || name.hasPrefix("wg") || name.hasPrefix("ipsec")

            if isActive {
                active.append(name)
            }

            if isTunnel && isActive {
                tunnels.append(name)
            }
        }

        return NetworkInterfaceSnapshot(
            activeInterfaces: CheckReport.unique(active).sorted(),
            tunnelInterfaces: CheckReport.unique(tunnels).sorted()
        )
    }

    private func durationMS(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}

private enum CommandRunner {
    static func run(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let command = ([executablePath] + arguments).joined(separator: " ")
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProbeError.commandFailed(command, message ?? "exit \(process.terminationStatus)")
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct CommercialIntelConfig: Decodable, Sendable {
    var ipinfoToken: String?

    static func load() -> CommercialIntelConfig {
        if let token = normalized(ProcessInfo.processInfo.environment["IPINFO_TOKEN"]) {
            return CommercialIntelConfig(ipinfoToken: token)
        }

        let configURL = HistoryStore.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("config.json")

        guard
            let data = try? Data(contentsOf: configURL),
            let config = try? JSONDecoder().decode(CommercialIntelConfig.self, from: data)
        else {
            return CommercialIntelConfig(ipinfoToken: nil)
        }

        return CommercialIntelConfig(ipinfoToken: normalized(config.ipinfoToken))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ProbeError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case badStatus(Int, String)
    case commandFailed(String, String)
    case sourceDisabled(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "无效 URL：\(url)"
        case .invalidResponse:
            "响应格式无效"
        case let .badStatus(status, body):
            body.isEmpty ? "HTTP \(status)" : "HTTP \(status)：\(body)"
        case let .commandFailed(command, message):
            "\(command) 失败：\(message)"
        case let .sourceDisabled(source):
            "\(source) 已关闭"
        }
    }
}

private struct IpifyResponse: Decodable, Sendable {
    var ip: String?
}

private struct IPWhoResponse: Decodable, Sendable {
    var ip: String?
    var success: Bool?
    var type: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var connection: Connection?
    var timezone: Timezone?

    enum CodingKeys: String, CodingKey {
        case ip
        case success
        case type
        case country
        case countryCode = "country_code"
        case region
        case city
        case connection
        case timezone
    }

    struct Connection: Decodable, Sendable {
        var asn: Int?
        var org: String?
        var isp: String?
        var domain: String?
    }

    struct Timezone: Decodable, Sendable {
        var id: String?
    }

    var observation: SourceObservation {
        SourceObservation(
            source: "ipwho.is",
            ip: ip,
            country: country,
            countryCode: countryCode,
            region: region,
            city: city,
            timezone: timezone?.id,
            asn: connection?.asn.map(String.init),
            organization: connection?.org,
            isp: connection?.isp,
            ipType: type
        )
    }
}

private struct IPAPIISResponse: Decodable, Sendable {
    var ip: String?
    var isDatacenter: Bool?
    var isMobile: Bool?
    var isTor: Bool?
    var isProxy: Bool?
    var isVPN: Bool?
    var isAbuser: Bool?
    var company: Company?
    var asn: ASN?
    var location: Location?

    enum CodingKeys: String, CodingKey {
        case ip
        case isDatacenter = "is_datacenter"
        case isMobile = "is_mobile"
        case isTor = "is_tor"
        case isProxy = "is_proxy"
        case isVPN = "is_vpn"
        case isAbuser = "is_abuser"
        case company
        case asn
        case location
    }

    struct Company: Decodable, Sendable {
        var name: String?
        var type: String?
        var abuserScore: String?

        enum CodingKeys: String, CodingKey {
            case name
            case type
            case abuserScore = "abuser_score"
        }
    }

    struct ASN: Decodable, Sendable {
        var asn: Int?
        var org: String?
        var descr: String?
        var country: String?
        var type: String?
        var abuserScore: String?

        enum CodingKeys: String, CodingKey {
            case asn
            case org
            case descr
            case country
            case type
            case abuserScore = "abuser_score"
        }
    }

    struct Location: Decodable, Sendable {
        var country: String?
        var countryCode: String?
        var state: String?
        var city: String?
        var timezone: String?

        enum CodingKeys: String, CodingKey {
            case country
            case countryCode = "country_code"
            case state
            case city
            case timezone
        }
    }

    var observation: SourceObservation {
        SourceObservation(
            source: "ipapi.is",
            ip: ip,
            country: location?.country,
            countryCode: location?.countryCode,
            region: location?.state,
            city: location?.city,
            timezone: location?.timezone,
            asn: asn?.asn.map(String.init),
            organization: asn?.org ?? company?.name,
            isp: asn?.descr,
            ipType: nil
        )
    }

    var security: SecuritySummary {
        SecuritySummary(
            isDatacenter: isDatacenter,
            isProxy: isProxy,
            isVPN: isVPN,
            isTor: isTor,
            isAbuser: isAbuser,
            isMobile: isMobile,
            companyType: company?.type ?? asn?.type,
            companyName: company?.name,
            companyAbuserScore: company?.abuserScore,
            asnAbuserScore: asn?.abuserScore
        )
    }
}

private struct IfconfigResponse: Decodable, Sendable {
    var ip: String?
    var country: String?
    var countryISO: String?
    var timeZone: String?
    var asn: String?
    var asnOrg: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case country
        case countryISO = "country_iso"
        case timeZone = "time_zone"
        case asn
        case asnOrg = "asn_org"
    }

    var observation: SourceObservation {
        SourceObservation(
            source: "ifconfig.co",
            ip: ip,
            country: country,
            countryCode: countryISO,
            region: nil,
            city: nil,
            timezone: timeZone,
            asn: asn,
            organization: asnOrg,
            isp: nil,
            ipType: nil
        )
    }
}

private struct IPInfoCoreResponse: Decodable, Sendable {
    var ip: String?
    var geo: Geo?
    var asInfo: ASInfo?
    var anonymous: Anonymous?
    var isAnonymous: Bool?
    var isHosting: Bool?
    var isMobile: Bool?
    var isSatellite: Bool?

    enum CodingKeys: String, CodingKey {
        case ip
        case geo
        case asInfo = "as"
        case anonymous
        case isAnonymous = "is_anonymous"
        case isHosting = "is_hosting"
        case isMobile = "is_mobile"
        case isSatellite = "is_satellite"
    }

    struct Geo: Decodable, Sendable {
        var city: String?
        var region: String?
        var country: String?
        var countryCode: String?
        var timezone: String?

        enum CodingKeys: String, CodingKey {
            case city
            case region
            case country
            case countryCode = "country_code"
            case timezone
        }
    }

    struct ASInfo: Decodable, Sendable {
        var asn: String?
        var name: String?
        var domain: String?
        var type: String?
    }

    struct Anonymous: Decodable, Sendable {
        var isProxy: Bool?
        var isRelay: Bool?
        var isTor: Bool?
        var isVPN: Bool?

        enum CodingKeys: String, CodingKey {
            case isProxy = "is_proxy"
            case isRelay = "is_relay"
            case isTor = "is_tor"
            case isVPN = "is_vpn"
        }
    }

    var observation: SourceObservation {
        SourceObservation(
            source: "IPinfo Core",
            ip: ip,
            country: geo?.country,
            countryCode: geo?.countryCode,
            region: geo?.region,
            city: geo?.city,
            timezone: geo?.timezone,
            asn: asInfo?.asn,
            organization: asInfo?.name,
            isp: asInfo?.domain,
            ipType: asInfo?.type
        )
    }

    var security: SecuritySummary {
        SecuritySummary(
            isDatacenter: isHosting,
            isProxy: anonymous?.isProxy ?? anonymous?.isRelay ?? isAnonymous,
            isVPN: anonymous?.isVPN,
            isTor: anonymous?.isTor,
            isAbuser: nil,
            isMobile: isMobile,
            companyType: asInfo?.type,
            companyName: asInfo?.name,
            companyAbuserScore: nil,
            asnAbuserScore: nil
        )
    }
}
