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
        let updater = Updater(session: URLSession(configuration: config), currentVersion: "0.0.1")
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        for (remote, expected) in [("0.0.2", true), ("1.0.0", true), ("0.10.0", true), ("0.0.1", false), ("0.0.0", false), ("0.0.2-rc.1", false), ("oops", false), ("0..2", false), ("0.1", false)] {
            check(Updater.isNewer(remote, than: "0.0.1") == expected, remote)
        }
        ReleaseProtocol.body = "{\"tag_name\":\"v0.0.2\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"extras.zip\",\"browser_download_url\":\"https://example.invalid/extras.zip\"}]}"
        await updater.checkForUpdates()
        check(updater.state == .available("0.0.2", Updater.releasesURL), "always link to our release page, never the first ZIP")
        check(ReleaseProtocol.seenURL?.absoluteString == "https://api.github.com/repos/Sherwin-NG/PiaoPal/releases/latest", "independent project endpoint")
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
        print("PASS: 0.0.1 version comparison, independent endpoint, safe release link, draft/prerelease exclusion, 404, HTTP errors and malformed JSON")
    }
}
