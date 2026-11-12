import Foundation
import CoreGraphics
import Security

protocol APIKeyStoring: AnyObject {
    func save(_ key: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

final class MemoryAPIKeyStore: APIKeyStoring {
    var values: [String: String] = [:]

    func save(_ key: String, account: String) throws { values[account] = key }

    func load(account: String) throws -> String? { values[account] }

    func delete(account: String) throws { values[account] = nil }
}

struct KeychainStoreError: Error, Equatable {
    var status: OSStatus
}

final class KeychainAPIKeyStore: APIKeyStoring {
    var service = "io.github.sherwinng.PiaoPal.custom-pet"

    func save(_ key: String, account: String) throws {
        try? delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStoreError(status: status) }
    }

    func load(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainStoreError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }
}

enum CustomPetProviderKind: String, Codable, CaseIterable, Equatable {
    case openAI = "openai"
}

struct CustomPetProviderSettings: Equatable {
    var kind: CustomPetProviderKind
    var model: String
    var baseURL: String
    var quality: String

    static let `default` = CustomPetProviderSettings(
        kind: .openAI,
        model: "gpt-image-1",
        baseURL: "https://api.openai.com/v1",
        quality: "medium"
    )

    func validated() -> (model: String, baseURL: URL, quality: String)? {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let quality = quality.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.count <= 80, !model.contains(where: \.isWhitespace) else { return nil }
        guard ["low", "medium", "high"].contains(quality) else { return nil }
        guard let url = Self.allowedBaseURL(baseURL) else { return nil }
        return (model, url, quality)
    }

    static func allowedBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", host == "localhost" || host == "127.0.0.1" { return url }
        return nil
    }
}

struct PetImageRequest: Equatable {
    var purpose: String
    var prompt: String
    var referencePNGs: [Data]
}

protocol PetImageGenerating: AnyObject {
    func generateImage(_ request: PetImageRequest) async throws -> Data
}

enum PetImageProviderError: Error, Equatable {
    case invalidConfiguration
    case undecodable
    case transport(retryable: Bool, status: Int, moderated: Bool, message: String)
}

enum OpenAIImageRequest {
    static func endpoint(baseURL: URL) -> URL {
        var text = baseURL.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text + "/images/edits")!
    }

    static func make(
        baseURL: URL,
        apiKey: String,
        model: String,
        prompt: String,
        images: [Data],
        quality: String,
        size: String,
        boundary: String = "PiaoPalCustomPetBoundary"
    ) -> URLRequest {
        var request = URLRequest(url: endpoint(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(
            model: model,
            prompt: prompt,
            images: images,
            quality: quality,
            size: size,
            boundary: boundary
        )
        return request
    }

    static func body(
        model: String,
        prompt: String,
        images: [Data],
        quality: String,
        size: String,
        boundary: String
    ) -> Data {
        var boundary = boundary
        let payload = images.reduce(into: Data()) { $0.append($1) }
        if payload.range(of: Data(boundary.utf8)) != nil { boundary += "-alt" }
        var data = Data()
        func field(_ name: String, _ value: String) {
            data.append(utf8("--\(boundary)\r\n"))
            data.append(utf8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"))
            data.append(utf8(value))
            data.append(utf8("\r\n"))
        }
        field("model", model)
        field("prompt", prompt)
        for (index, image) in images.enumerated() {
            data.append(utf8("--\(boundary)\r\n"))
            data.append(utf8(
                "Content-Disposition: form-data; name=\"image[]\"; filename=\"ref\(index).png\"\r\n"
            ))
            data.append(utf8("Content-Type: image/png\r\n\r\n"))
            data.append(image)
            data.append(utf8("\r\n"))
        }
        field("background", "transparent")
        field("output_format", "png")
        field("size", size)
        field("quality", quality)
        data.append(utf8("--\(boundary)--\r\n"))
        return data
    }

    static func parse(status: Int, body: Data, redact key: String) throws -> Data {
        if (200...299).contains(status) {
            struct Response: Decodable {
                struct Item: Decodable { var b64JSON: String?
                    enum CodingKeys: String, CodingKey { case b64JSON = "b64_json" }
                }
                var data: [Item]?
            }
            guard let decoded = try? JSONDecoder().decode(Response.self, from: body),
                  let encoded = decoded.data?.first?.b64JSON,
                  let image = Data(base64Encoded: encoded) else {
                throw PetImageProviderError.undecodable
            }
            return image
        }
        struct ErrorBody: Decodable {
            struct Detail: Decodable { var message: String?; var code: String? }
            var error: Detail?
        }
        let decoded = try? JSONDecoder().decode(ErrorBody.self, from: body)
        var message = decoded?.error?.message ?? (String(data: body, encoding: .utf8) ?? "")
        if message.count > 400 { message = String(message.prefix(400)) }
        if !key.isEmpty { message = message.replacingOccurrences(of: key, with: "••••") }
        let code = (decoded?.error?.code ?? "").lowercased()
        let lowered = message.lowercased()
        let moderated = code.contains("moderation") || code.contains("safety")
            || lowered.contains("moderation") || lowered.contains("safety")
        let retryable = !moderated && (status == 429 || status >= 500)
        throw PetImageProviderError.transport(
            retryable: retryable, status: status, moderated: moderated, message: message
        )
    }

    private static func utf8(_ text: String) -> Data { Data(text.utf8) }
}

final class OpenAIImageProvider: PetImageGenerating {
    var apiKey: String
    var model: String
    var baseURL: URL
    var quality: String
    var session: URLSession

    init(apiKey: String, model: String, baseURL: URL, quality: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.quality = quality
        self.session = session
    }

    func generateImage(_ request: PetImageRequest) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isNewline) else {
            throw PetImageProviderError.invalidConfiguration
        }
        let size = request.purpose == "reference" ? "1536x1024" : "1024x1024"
        do {
            return try await send(request, size: size, key: key)
        } catch let error as PetImageProviderError {
            if case .transport(_, let status, let moderated, _) = error,
               request.purpose == "reference", status == 400, !moderated, size != "1024x1024" {
                return try await send(request, size: "1024x1024", key: key)
            }
            throw error
        }
    }

    private func send(_ request: PetImageRequest, size: String, key: String) async throws -> Data {
        let urlRequest = OpenAIImageRequest.make(
            baseURL: baseURL,
            apiKey: key,
            model: model,
            prompt: request.prompt,
            images: request.referencePNGs,
            quality: quality,
            size: size
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PetImageProviderError.transport(
                retryable: true, status: 0, moderated: false, message: ""
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw PetImageProviderError.transport(retryable: true, status: 0, moderated: false, message: "")
        }
        do {
            return try OpenAIImageRequest.parse(status: http.statusCode, body: data, redact: key)
        } catch let error as PetImageProviderError {
            if case .transport(_, let status, _, _) = error {
                let line = "Custom pet image request failed purpose=\(request.purpose) status=\(status)"
                Log.skin.error("\(line, privacy: .public)")
            }
            throw error
        }
    }
}

enum CustomPetProviders {
    static func make(
        settings: CustomPetProviderSettings,
        apiKey: String,
        session: URLSession = .shared
    ) -> PetImageGenerating? {
        guard let valid = settings.validated() else { return nil }
        switch settings.kind {
        case .openAI:
            return OpenAIImageProvider(
                apiKey: apiKey,
                model: valid.model,
                baseURL: valid.baseURL,
                quality: valid.quality,
                session: session
            )
        }
    }
}

enum CustomPetCost {
    static func requestCount(includeWalkAtlas: Bool) -> Int {
        CustomPetLayout.purposes(includeWalkAtlas: includeWalkAtlas).count
    }

    /// Rough 2025 list price for a 1024 px `gpt-image-1` image. The reference sheet
    /// may be larger, and the provider can change the price. This is only a hint.
    static func estimatedUSD(includeWalkAtlas: Bool, quality: String) -> Double {
        let each: Double
        switch quality {
        case "low": each = 0.011
        case "high": each = 0.167
        default: each = 0.042
        }
        return Double(requestCount(includeWalkAtlas: includeWalkAtlas)) * each
    }
}

enum CustomPetPrompts {
    static func text(purpose: String, attempt: Int, previousFailure: String?) -> String {
        let pose = poseLine(purpose)
        var prompt = """
        The input images are photos of one real pet and, when present, a pixel-art character \
        reference of that same animal. Draw that animal only. Do not replace it with a generic \
        cat or a different species. \(pose)

        Pixel art with hard-edged color clusters, a limited palette, and a dark outline. No \
        anti-aliasing, no soft shadow, no ground, no wall, no text, no watermark, no frame, and \
        no checkerboard pattern. Every pixel outside the animal must be real transparency \
        (alpha 0). Keep the whole animal, including ears, paws, and tail, in the middle of the \
        image with a wide transparent margin. The interior of the animal is fully opaque.
        """
        if attempt > 1 || previousFailure != nil {
            let reason = previousFailure ?? "validation"
            prompt += " The previous image was rejected (\(reason)). Draw one smaller centered animal, leave a wider transparent margin, do not touch the image edges, and make this pose phase visibly different from the other frames."
        }
        return prompt
    }

    static func poseLine(_ purpose: String) -> String {
        if purpose == "reference" {
            return "Create one pixel-art character reference sheet of this pet: front, left profile, right profile, rear, and one three-quarter view. Match the photos' colors, markings, eyes, ears, and tail."
        }
        guard let separator = purpose.lastIndex(of: "_") else {
            return "Draw one full-body pixel-art sprite of this pet."
        }
        let name = String(purpose[..<separator])
        let index = Int(purpose[purpose.index(after: separator)...]) ?? 0
        if name.hasPrefix("gait_") {
            let direction = String(name.dropFirst("gait_".count))
            return "Draw ONE full-body walking sprite, \(directionPhrase(direction)). This is gait phase \(index) of 4 (0 and 2 are opposite contacts, 1 and 3 are passing steps). Alternate which legs are lifted. Keep the same body size in every phase."
        }
        switch name {
        case "idle":
            return "Draw ONE sprite of this pet sitting upright, front paws together, calm open eyes, facing the viewer."
        case "alert":
            return "Draw ONE sprite of this pet sitting, ears up, attentive open eyes, facing the viewer."
        case "tired":
            return "Draw ONE sprite of this pet sitting, eyes half closed, sleepy, facing the viewer."
        case "sleeping":
            return "Draw ONE sprite of this pet curled up asleep, eyes closed, head on the same side in every sleeping frame. Phase \(index) changes only a very small breath. Do not flip the body."
        case "scratchSelf":
            return "Draw ONE sprite of this pet sitting and scratching its own ear with a hind paw. Phase \(index) of 3 must show a different paw position."
        case "scratchWallN":
            return "Draw ONE sprite standing on its hind legs, facing directly away from the viewer, both front paws raised as if scratching above. No wall is visible. Phase \(index)."
        case "scratchWallS":
            return "Draw ONE sprite standing on its hind legs, facing the viewer, both front paws raised as if scratching above. No wall is visible. Phase \(index)."
        case "scratchWallE":
            return "Draw ONE sprite in right-facing profile, standing on its hind legs, front paws raised as if scratching to the right. No wall is visible. Phase \(index)."
        case "scratchWallW":
            return "Draw ONE sprite in left-facing profile, standing on its hind legs, front paws raised as if scratching to the left. No wall is visible. Phase \(index)."
        default:
            let phase = index == 0 ? "the first contact pose" : "the opposite step, with the other legs lifted"
            return "Draw ONE full-body walking sprite, \(directionPhrase(name)). Use \(phase). Keep the same body size."
        }
    }

    static func directionPhrase(_ direction: String) -> String {
        switch direction {
        case "N": return "facing directly away from the viewer so the back and both ears are visible and the face is not"
        case "S": return "facing directly toward the viewer so the face is visible"
        case "E": return "in a right-facing profile"
        case "W": return "in a left-facing profile"
        case "NE": return "in a rear three-quarter view with the head toward the upper right, face hidden"
        case "NW": return "in a rear three-quarter view with the head toward the upper left, face hidden"
        case "SE": return "in a front three-quarter view with the face visible and the head toward the lower right"
        case "SW": return "in a front three-quarter view with the face visible and the head toward the lower left"
        default: return "in a clear full-body pose"
        }
    }
}

struct CustomPetProgress: Equatable {
    var completed: Int
    var total: Int
    var purpose: String
}

struct CustomPetPipelineResult: Equatable {
    var mainPNG: Data?
    var walkPNG: Data?
    var frames: [String: Data]
    var failures: [String: String]
    var attempts: [String: Int]
    var cancelled: Bool
}

final class CustomPetPipeline {
    var maxAttempts: Int
    let provider: PetImageGenerating
    let photos: [PreparedPhoto]

    init(provider: PetImageGenerating, photos: [PreparedPhoto], maxAttempts: Int = 3) {
        self.provider = provider
        self.photos = photos
        self.maxAttempts = max(1, maxAttempts)
    }

    func run(
        includeWalkAtlas: Bool,
        existing: [String: Data] = [:],
        onProgress: @escaping (CustomPetProgress) -> Void = { _ in }
    ) async -> CustomPetPipelineResult {
        let purposes = CustomPetLayout.purposes(includeWalkAtlas: includeWalkAtlas)
        var accepted = existing.filter { purposes.contains($0.key) }
        var attempts: [String: Int] = [:]
        var reasons: [String: String] = [:]
        var cancelled = false

        func emit(_ purpose: String) {
            let completed = purposes.filter { accepted[$0] != nil }.count
            onProgress(CustomPetProgress(completed: completed, total: purposes.count, purpose: purpose))
        }

        while !cancelled && !Task.isCancelled {
            if let problem = consistencyProblem(accepted: accepted, includeWalkAtlas: includeWalkAtlas) {
                accepted[problem.purpose] = nil
                reasons[problem.purpose] = problem.reason
                continue
            }
            if purposes.allSatisfy({ accepted[$0] != nil }) {
                switch pack(accepted, includeWalkAtlas: includeWalkAtlas) {
                case .success(let main, let walk):
                    return CustomPetPipelineResult(
                        mainPNG: main, walkPNG: walk, frames: accepted,
                        failures: [:], attempts: attempts, cancelled: false
                    )
                case .reject(let purpose, let reason):
                    guard purposes.contains(purpose), attempts[purpose, default: 0] < maxAttempts else {
                        var failures = [purpose: reason]
                        for item in purposes where accepted[item] == nil {
                            failures[item] = reasons[item] ?? reason
                        }
                        return CustomPetPipelineResult(
                            mainPNG: nil, walkPNG: nil, frames: accepted,
                            failures: failures, attempts: attempts, cancelled: false
                        )
                    }
                    accepted[purpose] = nil
                    reasons[purpose] = reason
                    continue
                case .fatal(let reason):
                    return CustomPetPipelineResult(
                        mainPNG: nil, walkPNG: nil, frames: accepted,
                        failures: ["atlas": reason], attempts: attempts, cancelled: false
                    )
                }
            }

            let pending = purposes.filter { accepted[$0] == nil && attempts[$0, default: 0] < maxAttempts }
            guard let purpose = pending.first(where: { $0 == "reference" }) ?? pending.first else { break }
            attempts[purpose, default: 0] += 1
            emit(purpose)
            let prompt = CustomPetPrompts.text(
                purpose: purpose,
                attempt: attempts[purpose] ?? 1,
                previousFailure: reasons[purpose]
            )
            let refs = referenceImages(for: purpose, accepted: accepted)
            do {
                let data = try await provider.generateImage(PetImageRequest(
                    purpose: purpose, prompt: prompt, referencePNGs: refs
                ))
                guard let image = RGBAImageCodec.cgImage(data: data) else {
                    reasons[purpose] = GeneratedImageIssue.unreadable.rawValue
                    continue
                }
                let issues = SpriteValidator.inspectGenerated(image)
                if let issue = issues.first {
                    reasons[purpose] = issue.rawValue
                } else {
                    accepted[purpose] = data
                    reasons[purpose] = nil
                }
            } catch is CancellationError {
                cancelled = true
            } catch let error as PetImageProviderError {
                switch error {
                case .invalidConfiguration:
                    reasons[purpose] = "provider"
                    attempts[purpose] = maxAttempts
                case .undecodable:
                    reasons[purpose] = GeneratedImageIssue.unreadable.rawValue
                case .transport(let retryable, _, let moderated, _):
                    if moderated {
                        reasons[purpose] = "moderation"
                        attempts[purpose] = maxAttempts
                        return CustomPetPipelineResult(
                            mainPNG: nil, walkPNG: nil, frames: accepted,
                            failures: [purpose: "moderation"], attempts: attempts, cancelled: false
                        )
                    } else if retryable {
                        reasons[purpose] = "network"
                    } else {
                        reasons[purpose] = "provider"
                        attempts[purpose] = maxAttempts
                    }
                }
            } catch {
                reasons[purpose] = "network"
            }
        }

        if Task.isCancelled { cancelled = true }
        var failures: [String: String] = [:]
        for purpose in purposes where accepted[purpose] == nil {
            failures[purpose] = reasons[purpose] ?? (cancelled ? "cancelled" : "validation")
        }
        return CustomPetPipelineResult(
            mainPNG: nil, walkPNG: nil, frames: accepted,
            failures: failures, attempts: attempts, cancelled: cancelled
        )
    }

    private func referenceImages(for purpose: String, accepted: [String: Data]) -> [Data] {
        if purpose == "reference" { return photos.map(\.pngData) }
        var images: [Data] = []
        if let reference = accepted["reference"] { images.append(reference) }
        images.append(contentsOf: photos.prefix(2).map(\.pngData))
        return images
    }

    private func consistencyProblem(
        accepted: [String: Data],
        includeWalkAtlas: Bool
    ) -> (purpose: String, reason: String)? {
        for (group, members) in CustomPetLayout.consistencyGroups(includeWalkAtlas: includeWalkAtlas) {
            guard members.allSatisfy({ accepted[$0] != nil }) else { continue }
            let frames: [(purpose: String, image: CGImage)] = members.compactMap { purpose in
                guard let data = accepted[purpose], let image = RGBAImageCodec.cgImage(data: data) else { return nil }
                return (purpose, image)
            }
            guard frames.count == members.count else {
                let missing = members.first { accepted[$0] == nil } ?? members[0]
                return (missing, GeneratedImageIssue.unreadable.rawValue)
            }
            if let issue = SpriteValidator.consistencyIssues(group: group, frames: frames) {
                return (issue.purpose, issue.issue.rawValue)
            }
        }
        return nil
    }

    private enum PackOutcome {
        case success(Data, Data?)
        case reject(String, String)
        case fatal(String)
    }

    private func pack(_ accepted: [String: Data], includeWalkAtlas: Bool) -> PackOutcome {
        let packed: (mainPNG: Data, walkPNG: Data?)
        do {
            packed = try SpriteAtlasAssembler.pack(framePNGs: accepted, includeWalkAtlas: includeWalkAtlas)
        } catch let error as AtlasPackError {
            switch error {
            case .missing(let purpose), .unreadable(let purpose), .overflow(let purpose):
                return .reject(purpose, error.reason)
            case .encodeFailed:
                return .fatal("encode")
            }
        } catch {
            return .fatal("encode")
        }
        guard let main = RGBAImageCodec.cgImage(data: packed.mainPNG) else { return .fatal("encode") }
        let mainIssues = SpriteValidator.inspectAtlas(main, kind: .main, includeWalkAtlas: includeWalkAtlas)
        if let issue = mainIssues.first { return .reject(issue.purpose, issue.issue.rawValue) }
        if let walkPNG = packed.walkPNG {
            guard let walk = RGBAImageCodec.cgImage(data: walkPNG) else { return .fatal("encode") }
            let walkIssues = SpriteValidator.inspectAtlas(walk, kind: .walk, includeWalkAtlas: true)
            if let issue = walkIssues.first { return .reject(issue.purpose, issue.issue.rawValue) }
        }
        return .success(packed.mainPNG, packed.walkPNG)
    }
}

private extension AtlasPackError {
    var reason: String {
        switch self {
        case .missing: return "missing"
        case .unreadable: return GeneratedImageIssue.unreadable.rawValue
        case .overflow: return GeneratedImageIssue.cellEdge.rawValue
        case .encodeFailed: return "encode"
        }
    }
}
