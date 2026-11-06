import Foundation
import AppKit

/// Checks this distribution's releases. Installation stays in the user's hands:
/// the release page provides verified macOS packages.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String, URL)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    static let releasesURL = URL(string: "https://github.com/Sherwin-NG/PiaoPal/releases/latest")!
    private let repoAPI = URL(string: "https://api.github.com/repos/Sherwin-NG/PiaoPal/releases/latest")!
    private let session: URLSession
    let currentVersion: String

    init(session: URLSession = .shared, currentVersion: String? = nil) {
        self.session = session
        self.currentVersion = currentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.2.0"
    }

    func checkForUpdates() async {
        state = .checking
        do {
            var request = URLRequest(url: repoAPI)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("PiaoPal/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            // A new public project can legitimately have no published releases yet.
            if response.statusCode == 404 { state = .upToDate; return }
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }

            struct Release: Decodable {
                let tag_name: String
                let draft: Bool
                let prerelease: Bool
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let remote = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst()) : release.tag_name
            guard !release.draft, !release.prerelease,
                  Self.isNewer(remote, than: currentVersion) else {
                state = .upToDate
                return
            }
            state = .available(remote, Self.releasesURL)
        } catch {
            Log.store.error("Update check failed: \(error.localizedDescription, privacy: .private)")
            state = .error("update.error")
        }
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        func components(_ value: String) -> [Int]? {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let numbers = parts.compactMap { part -> Int? in
                guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
                return Int(part)
            }
            return numbers.count == 3 ? numbers : nil
        }
        guard let remote = components(remote), let local = components(local) else { return false }
        return local.lexicographicallyPrecedes(remote)
    }
}
