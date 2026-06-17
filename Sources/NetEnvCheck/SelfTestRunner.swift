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

        var strictReport = baseReport()
        strictReport.scoringPreset = .strict
        strictReport.security.isProxy = true
        expect(strictReport.riskScore == 58, "strict proxy score should be 58")
        expect(strictReport.scoreBreakdown.contains { $0.id == "proxy" && $0.points == -42 }, "strict proxy penalty should be scaled")
        expect(strictReport.riskBand == .high, "strict proxy report should be high risk")

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
