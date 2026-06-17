import Foundation

struct AppVersion: Comparable, Equatable, Sendable {
    var rawValue: String
    private var components: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? rawValue

        components = normalized
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)

        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct UpdateRelease: Identifiable, Equatable, Sendable {
    var id: String { tagName }
    var tagName: String
    var version: String
    var name: String
    var body: String
    var publishedAt: Date?
    var htmlURL: URL
    var assetName: String
    var assetDownloadURL: URL
    var assetSize: Int
    var currentVersion: String

    var isNewerThanCurrent: Bool {
        AppVersion(version) > AppVersion(currentVersion)
    }

    var displayTitle: String {
        name.isEmpty ? tagName : name
    }

    var assetSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(assetSize), countStyle: .file)
    }
}

struct DownloadedUpdate: Equatable, Sendable {
    var fileURL: URL
    var expectedSize: Int
    var actualSize: Int

    var isSizeVerified: Bool {
        expectedSize <= 0 || expectedSize == actualSize
    }

    var actualSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(actualSize), countStyle: .file)
    }
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case releaseAssetMissing
    case downloadedFileSizeMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "无法读取 GitHub Releases，请检查网络后重试。"
        case .releaseAssetMissing:
            "最新 Release 中没有找到 NetEnvCheck.app.zip 发布包。"
        case let .downloadedFileSizeMismatch(expected, actual):
            "下载包大小不一致，预期 \(ByteCountFormatter.string(fromByteCount: Int64(expected), countStyle: .file))，实际 \(ByteCountFormatter.string(fromByteCount: Int64(actual), countStyle: .file))。请重新下载。"
        }
    }
}

enum UpdateChecker {
    static let repository = "xie8266509/NetEnvCheck"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/xie8266509/NetEnvCheck/releases/latest")!
    static let fallbackCurrentVersion = "1.6.0"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackCurrentVersion
    }

    static func checkLatestRelease(currentVersion: String = Self.currentVersion) async throws -> UpdateRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("NetEnvCheck", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }

        return try decodeRelease(data, currentVersion: currentVersion)
    }

    static func decodeRelease(_ data: Data, currentVersion: String = Self.currentVersion) throws -> UpdateRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)

        guard
            let htmlURL = URL(string: release.htmlURL),
            let asset = release.assets.first(where: { $0.name == "NetEnvCheck.app.zip" }),
            let assetURL = URL(string: asset.browserDownloadURL)
        else {
            throw UpdateCheckError.releaseAssetMissing
        }

        return UpdateRelease(
            tagName: release.tagName,
            version: release.tagName.trimmingPrefix("v"),
            name: release.name ?? release.tagName,
            body: release.body ?? "",
            publishedAt: release.publishedAt,
            htmlURL: htmlURL,
            assetName: asset.name,
            assetDownloadURL: assetURL,
            assetSize: asset.size,
            currentVersion: currentVersion
        )
    }

    static func downloadAppZip(from release: UpdateRelease) async throws -> DownloadedUpdate {
        var request = URLRequest(url: release.assetDownloadURL)
        request.timeoutInterval = 60
        request.setValue("NetEnvCheck", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        let destination = downloads.appendingPathComponent("NetEnvCheck-\(release.tagName).app.zip")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let actualSize = attributes[.size] as? Int ?? 0

        guard release.assetSize <= 0 || actualSize == release.assetSize else {
            try? FileManager.default.removeItem(at: destination)
            throw UpdateCheckError.downloadedFileSizeMismatch(expected: release.assetSize, actual: actualSize)
        }

        return DownloadedUpdate(fileURL: destination, expectedSize: release.assetSize, actualSize: actualSize)
    }
}

private struct GitHubRelease: Codable {
    var tagName: String
    var name: String?
    var body: String?
    var htmlURL: String
    var publishedAt: Date?
    var assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAsset: Codable {
    var name: String
    var browserDownloadURL: String
    var size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
