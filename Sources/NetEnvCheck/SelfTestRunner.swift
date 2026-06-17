import Foundation

enum SelfTestRunner {
    static func run() -> Int32 {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        expect(IPAddressClassifier.isPublic("8.8.8.8"), "8.8.8.8 should be public")
        expect(!IPAddressClassifier.isPublic("10.0.0.1"), "10.0.0.1 should be private")
        expect(!IPAddressClassifier.isPublic("172.16.0.1"), "172.16.0.1 should be private")
        expect(!IPAddressClassifier.isPublic("192.168.1.1"), "192.168.1.1 should be private")
        expect(!IPAddressClassifier.isPublic("127.0.0.1"), "127.0.0.1 should be private")

        var datacenterReport = baseReport()
        datacenterReport.security.isDatacenter = true
        expect(datacenterReport.riskScore == 78, "datacenter score should be 78")
        expect(datacenterReport.scoreBreakdown.contains { $0.id == "datacenter" && $0.points == -22 }, "datacenter penalty should be explained")
        expect(datacenterReport.riskBand == .medium, "datacenter report should be medium risk")
        expect(datacenterReport.remediationPlans.contains { $0.id == "datacenter" }, "datacenter remediation plan should be generated")
        expect(datacenterReport.remediationGuide().contains("更换住宅或移动出口"), "remediation guide should include datacenter plan")

        var strictReport = baseReport()
        strictReport.scoringPreset = .strict
        strictReport.security.isProxy = true
        expect(strictReport.riskScore == 58, "strict proxy score should be 58")
        expect(strictReport.scoreBreakdown.contains { $0.id == "proxy" && $0.points == -42 }, "strict proxy penalty should be scaled")
        expect(strictReport.riskBand == .high, "strict proxy report should be high risk")
        expect(strictReport.remediationPlans.contains { $0.id == "proxy-vpn-tor" }, "proxy remediation plan should be generated")

        var conflictReport = baseReport()
        conflictReport.observations.append(
            SourceObservation(
                source: "ifconfig.co",
                ip: "203.0.113.10",
                country: "Canada",
                countryCode: "CA",
                region: nil,
                city: nil,
                timezone: nil,
                asn: nil,
                organization: nil,
                isp: nil,
                ipType: nil
            )
        )
        conflictReport.sourceStatuses = [
            SourceStatus(source: "ipwho.is", url: "https://ipwho.is/", state: .success, durationMS: 120, errorMessage: nil),
            SourceStatus(source: "ifconfig.co", url: "https://ifconfig.co/json", state: .success, durationMS: 160, errorMessage: nil)
        ]
        expect(conflictReport.countryConflict, "country conflict should be detected")
        expect(conflictReport.confidence == .medium, "conflicting countries should lower confidence")
        expect(conflictReport.scoreBreakdown.contains { $0.id == "country-conflict" }, "country conflict should be explained")
        expect(conflictReport.remediationPlans.contains { $0.id == "country-conflict" }, "country conflict remediation should be generated")

        var settingsReport = baseReport()
        settingsReport.localTimezone = "America/Los_Angeles"
        settingsReport.preferredLanguage = "zh-CN"
        settingsReport.browser.language = "zh-CN"
        settingsReport.browser.httpHeaders = ["Accept-Language": "zh-CN,zh;q=0.9"]
        settingsReport.dns.nameservers = ["1.1.1.1"]
        expect(settingsReport.scoreBreakdown.contains { $0.id == "system-timezone" }, "system timezone mismatch should be scored")
        expect(settingsReport.scoreBreakdown.contains { $0.id == "system-language" }, "system language mismatch should be scored")
        expect(settingsReport.scoreBreakdown.contains { $0.id == "dns" }, "DNS resolver risk should be scored")
        expect(settingsReport.remediationPlans.contains { $0.id == "timezone" }, "timezone remediation plan should be generated")
        expect(settingsReport.remediationPlans.contains { $0.id == "language" }, "language remediation plan should be generated")
        expect(settingsReport.remediationPlans.contains { $0.id == "dns" }, "DNS remediation plan should be generated")
        expect(settingsReport.estimatedRemediationGain >= 27, "estimated remediation gain should include settings plans")

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NetEnvCheckTests-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        var historyReport = CheckReport()
        historyReport.publicIP = "8.8.8.8"
        historyReport.scoringPreset = .relaxed
        let saved = store.append(historyReport)
        let loaded = store.load()
        expect(saved.count == 1, "history append should return one report")
        expect(loaded.count == 1, "history load should return one report")
        expect(loaded.first?.report.publicIP == "8.8.8.8", "history should preserve public IP")
        expect(loaded.first?.report.scoringPreset == .relaxed, "history should preserve preset")

        if let id = loaded.first?.id {
            let afterDelete = store.delete(id: id)
            expect(afterDelete.isEmpty, "history delete should remove selected report")
        }
        store.clear()
        expect(store.load().isEmpty, "history clear should remove all reports")

        var settings = AppSettings()
        settings.historyLimit = 1
        settings.networkTimeoutSeconds = 99
        settings.retryCount = 8
        let normalized = settings.normalized
        expect(normalized.historyLimit == 10, "settings should clamp history limit")
        expect(normalized.networkTimeoutSeconds == 30, "settings should clamp timeout")
        expect(normalized.retryCount == 3, "settings should clamp retry count")

        let html = baseReport().htmlReport()
        expect(html.contains("<!doctype html>"), "HTML report should render a document")
        expect(html.contains("网络环境检测报告"), "HTML report should include report title")

        if failures.isEmpty {
            print("NetEnvCheck self-tests passed")
            return 0
        }

        failures.forEach { failure in
            fputs("Self-test failed: \(failure)\n", stderr)
        }
        return 1
    }

    private static func baseReport() -> CheckReport {
        var report = CheckReport()
        report.publicIP = "203.0.113.10"
        report.localTimezone = "America/New_York"
        report.preferredLanguage = "en-US"
        report.observations = [
            SourceObservation(
                source: "ipwho.is",
                ip: "203.0.113.10",
                country: "United States",
                countryCode: "US",
                region: "New York",
                city: "New York",
                timezone: "America/New_York",
                asn: "64500",
                organization: "Example Hosting",
                isp: nil,
                ipType: "IPv4"
            )
        ]
        return report
    }
}
