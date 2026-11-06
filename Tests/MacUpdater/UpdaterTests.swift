import Foundation

final class ReleaseProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    static var seenURL: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seenURL = request.url
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct UpdateTests {
    @MainActor static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        let updater = Updater(session: URLSession(configuration: config), currentVersion: "0.0.3")
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        for (remote, expected) in [("0.1.0", true), ("1.0.0", true), ("0.10.0", true), ("0.0.3", false), ("0.0.2", false), ("0.1.0-rc.1", false), ("oops", false), ("0..2", false), ("0.1", false)] {
            check(Updater.isNewer(remote, than: "0.0.3") == expected, remote)
        }
        check(!Updater.isNewer("0.1.0", than: "0.1.0"), "same current release is not an update")
        check(Updater.isNewer("0.2.0", than: "0.1.0"), "0.1.0 users can update to 0.2.0")
        check(!Updater.isNewer("0.2.0", than: "0.2.0"), "0.2.0 does not offer itself as an update")
        ReleaseProtocol.body = "{\"tag_name\":\"v0.1.0\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"extras.zip\",\"browser_download_url\":\"https://example.invalid/extras.zip\"}]}"
        await updater.checkForUpdates()
        check(updater.state == .available("0.1.0", Updater.releasesURL), "always link to our release page, never the first ZIP")
        check(ReleaseProtocol.seenURL?.absoluteString == "https://api.github.com/repos/Sherwin-NG/PiaoPal/releases/latest", "independent project endpoint")
        ReleaseProtocol.body = "{\"tag_name\":\"v0.2.0\",\"draft\":false,\"prerelease\":false}"
        let previousRelease = Updater(session: URLSession(configuration: config), currentVersion: "0.1.0")
        await previousRelease.checkForUpdates()
        check(previousRelease.state == .available("0.2.0", Updater.releasesURL), "previous release discovers 0.2.0")
        let currentRelease = Updater(session: URLSession(configuration: config), currentVersion: "0.2.0")
        await currentRelease.checkForUpdates()
        check(currentRelease.state == .upToDate, "current release is up to date")
        for flag in ["draft", "prerelease"] {
            ReleaseProtocol.body = "{\"tag_name\":\"v9.0.0\",\"draft\":false,\"prerelease\":false}".replacingOccurrences(of: "\"\(flag)\":false", with: "\"\(flag)\":true")
            await updater.checkForUpdates()
            check(updater.state == .upToDate, "do not offer \(flag)")
        }
        ReleaseProtocol.status = 404
        await updater.checkForUpdates()
        check(updater.state == .upToDate, "no published releases")
        ReleaseProtocol.status = 403
        await updater.checkForUpdates()
        check(updater.state == .error("update.error"), "rate limit is a localizable error")
        ReleaseProtocol.status = 200
        ReleaseProtocol.body = "bad JSON"
        await updater.checkForUpdates()
        check(updater.state == .error("update.error"), "invalid response")
        print("PASS: 0.0.3 to 0.1.0 and 0.1.0 to 0.2.0 updates, version comparison, independent endpoint, safe release link, draft/prerelease exclusion, 404, HTTP errors and malformed JSON")
    }
}
