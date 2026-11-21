import AppKit
import Foundation
import TitizCore

struct AvailableUpdate: Equatable, Sendable {
    let version: SemanticVersion
    let tagName: String
    let zipAssetURL: URL?
    let releasePageURL: URL
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(AvailableUpdate)
    case downloading(version: String, progress: Double?)
    case installing(version: String)
    case failed(String)
}

enum AppUpdateError: LocalizedError {
    case networkUnavailable
    case rateLimited
    case httpStatus(Int)
    case invalidReleasePayload
    case missingDownloadAsset
    case invalidBundlePackage(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "İnternet bağlantısı kurulamadı."
        case .rateLimited:
            return "GitHub API istek sınırına ulaşıldı; lütfen biraz sonra tekrar deneyin."
        case let .httpStatus(code):
            return "Güncelleme sunucusundan beklenmeyen yanıt alındı (HTTP \(code))."
        case .invalidReleasePayload:
            return "Sürüm bilgisi okunamadı."
        case .missingDownloadAsset:
            return "Bu sürüm için indirilebilir macOS (.zip) paketi bulunamadı."
        case let .invalidBundlePackage(detail):
            return "Güncelleme paketi doğrulanamadı: \(detail)"
        case .permissionDenied:
            return "Mevcut Titiz.app konumu yazılabilir değil; sürüm sayfası tarayıcıda açılabilir."
        }
    }
}

/// Privacy-preserving, user-initiated GitHub Releases updater.
/// Makes zero network calls on launch or during proofreading; only runs when requested from Settings.
enum AppUpdater {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/GorkemSay/Titiz/releases/latest")!
    private static let fallbackReleasesPageURL = URL(string: "https://github.com/GorkemSay/Titiz/releases")!

    private struct GitHubReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    static var currentVersionString: String {
        if let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = short.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "1.0.0"
    }

    static var currentVersion: SemanticVersion {
        SemanticVersion(parsing: currentVersionString) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
    }

    static func canSelfInstallFromCurrentBundle() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return false }
        let parentDir = bundleURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parentDir)
    }

    static func isTrustedGitHubURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" ||
            host.hasSuffix(".github.com") ||
            host == "githubusercontent.com" ||
            host.hasSuffix(".githubusercontent.com")
    }

    /// Checks GitHub Releases API for a newer version than `currentVersion`.
    /// Returns `nil` when up to date or no release has been published yet (`HTTP 404`).
    static func fetchLatestUpdate(
        currentVersion: SemanticVersion = currentVersion,
        session: URLSession = .shared
    ) async throws -> AvailableUpdate? {
        var request = URLRequest(
            url: latestReleaseURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Titiz-macOS/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            throw AppUpdateError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidReleasePayload
        }

        switch http.statusCode {
        case 200:
            break
        case 404:
            // Repository has not published a GitHub Release yet; report cleanly as up to date.
            return nil
        case 403:
            throw AppUpdateError.rateLimited
        default:
            throw AppUpdateError.httpStatus(http.statusCode)
        }

        guard let payload = try? JSONDecoder().decode(GitHubReleasePayload.self, from: data),
              !payload.draft,
              let latestVersion = SemanticVersion(parsing: payload.tagName) else {
            throw AppUpdateError.invalidReleasePayload
        }

        guard latestVersion > currentVersion else {
            return nil
        }

        let releasePageURL: URL
        if let parsedPage = URL(string: payload.htmlURL), isTrustedGitHubURL(parsedPage) {
            releasePageURL = parsedPage
        } else {
            releasePageURL = fallbackReleasesPageURL
        }

        let trustedZipURLs: [(name: String, url: URL)] = payload.assets.compactMap { asset in
            guard asset.name.lowercased().hasSuffix(".zip"),
                  let url = URL(string: asset.browserDownloadURL),
                  isTrustedGitHubURL(url) else {
                return nil
            }
            return (asset.name, url)
        }

        let preferredZipURL =
            trustedZipURLs.first(where: { $0.name.lowercased().contains("titiz") })?.url ??
            trustedZipURLs.first?.url

        return AvailableUpdate(
            version: latestVersion,
            tagName: payload.tagName,
            zipAssetURL: preferredZipURL,
            releasePageURL: releasePageURL
        )
    }

    /// Streams the release `.zip` archive into a staging directory, unpacks it with `ditto`,
    /// verifies bundle metadata (`CFBundleIdentifier`, `CFBundleExecutable`), and checks `codesign`.
    static func downloadAndStageUpdate(
        _ update: AvailableUpdate,
        onProgress: @escaping @MainActor @Sendable (Double?) -> Void
    ) async throws -> (stagedAppURL: URL, stagingDir: URL) {
        guard let zipURL = update.zipAssetURL, isTrustedGitHubURL(zipURL) else {
            throw AppUpdateError.missingDownloadAsset
        }

        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("TitizUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        do {
            let zipFileURL = stagingDir.appendingPathComponent("Titiz-update.zip")
            var request = URLRequest(
                url: zipURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 60
            )
            request.setValue("Titiz-macOS/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await URLSession.shared.bytes(for: request)
            } catch let urlError as URLError {
                if urlError.code == .cancelled { throw CancellationError() }
                throw AppUpdateError.networkUnavailable
            }

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw AppUpdateError.httpStatus(code)
            }

            let expectedBytes = http.expectedContentLength > 0 ? Double(http.expectedContentLength) : nil
            fm.createFile(atPath: zipFileURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: zipFileURL)
            defer { try? handle.close() }

            var buffer = Data()
            buffer.reserveCapacity(65_536)
            var totalDownloaded: Int64 = 0
            var lastReportedBytes: Int64 = 0

            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                totalDownloaded += 1

                if buffer.count >= 65_536 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                if totalDownloaded - lastReportedBytes >= 131_072 {
                    lastReportedBytes = totalDownloaded
                    let ratio = expectedBytes.map { min(1.0, Double(totalDownloaded) / $0) }
                    await onProgress(ratio)
                }
            }

            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
            await onProgress(expectedBytes != nil ? 1.0 : nil)

            let extractDir = stagingDir.appendingPathComponent("extracted", isDirectory: true)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let dittoStatus = try await runProcess(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", zipFileURL.path, extractDir.path]
            )
            guard dittoStatus == 0 else {
                throw AppUpdateError.invalidBundlePackage("arşiv açılamadı")
            }

            guard let stagedAppURL = findTitizAppBundle(in: extractDir) else {
                throw AppUpdateError.invalidBundlePackage("Titiz.app bulunamadı")
            }

            try validateStagedAppBundle(at: stagedAppURL)

            let verifyStatus = try await runProcess(
                executablePath: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", stagedAppURL.path]
            )
            guard verifyStatus == 0 else {
                throw AppUpdateError.invalidBundlePackage("uygulama imzası doğrulanamadı")
            }

            return (stagedAppURL, stagingDir)
        } catch {
            try? fm.removeItem(at: stagingDir)
            throw error
        }
    }

    @MainActor
    static func replaceCurrentBundleAndRelaunch(stagedAppURL: URL, stagingDir: URL) throws {
        guard canSelfInstallFromCurrentBundle() else {
            try? FileManager.default.removeItem(at: stagingDir)
            throw AppUpdateError.permissionDenied
        }

        let targetAppURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        PID="$1"
        TARGET="$2"
        STAGED="$3"
        WORKDIR="$4"
        BACKUP="${TARGET}.titiz-backup.$$"
        COUNT=0
        while kill -0 "$PID" 2>/dev/null; do
          COUNT=$((COUNT + 1))
          if [ "$COUNT" -gt 100 ]; then
            break
          fi
          sleep 0.1
        done
        rm -rf "$BACKUP"
        if [ -e "$TARGET" ]; then
          if ! mv "$TARGET" "$BACKUP"; then
            rm -rf "$WORKDIR"
            exit 1
          fi
        fi
        if mv "$STAGED" "$TARGET"; then
          rm -rf "$BACKUP"
          rm -rf "$WORKDIR"
          open -n "$TARGET"
        else
          if [ -e "$BACKUP" ] && [ ! -e "$TARGET" ]; then
            mv "$BACKUP" "$TARGET"
          fi
          rm -rf "$WORKDIR"
          exit 1
        fi
        """

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "titiz-updater", "\(pid)", targetAppURL.path, stagedAppURL.path, stagingDir.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()

        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private static func findTitizAppBundle(in rootDir: URL) -> URL? {
        let directCandidate = rootDir.appendingPathComponent("Titiz.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: directCandidate.path) {
            return directCandidate
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        while let item = enumerator.nextObject() as? URL {
            if enumerator.level > 3 {
                enumerator.skipDescendants()
                continue
            }
            if item.lastPathComponent == "Titiz.app" {
                return item
            }
        }
        return nil
    }

    private static func validateStagedAppBundle(at appURL: URL) throws {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw AppUpdateError.invalidBundlePackage("Info.plist okunamadı")
        }

        guard let bundleID = dict["CFBundleIdentifier"] as? String,
              bundleID == "com.gorkemsay.Titiz",
              let executable = dict["CFBundleExecutable"] as? String,
              executable == "TitizApp" else {
            throw AppUpdateError.invalidBundlePackage("beklenen paket kimliği eşleşmedi")
        }

        let execURL = appURL.appendingPathComponent("Contents/MacOS/TitizApp")
        guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
            throw AppUpdateError.invalidBundlePackage("çalıştırılabilir dosya eksik")
        }
    }

    private static func runProcess(executablePath: String, arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
