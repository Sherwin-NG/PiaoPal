import AppKit
import SwiftUI

@MainActor
final class CustomPetStudioModel: ObservableObject {
    enum Step: Equatable {
        case library
        case photos
        case generating
        case preview
        case failed
    }

    @Published var step: Step = .library
    @Published var displayName = ""
    @Published var photos: [PreparedPhoto] = []
    @Published var issues: [PhotoPrepIssue] = []
    @Published var includeWalkAtlas = true
    @Published var modelName: String
    @Published var baseURL: String
    @Published var quality: String
    @Published var apiKeyDraft = ""
    @Published var keySaved = false
    @Published var keychainFailed = false
    @Published var progress = CustomPetProgress(completed: 0, total: 0, purpose: "")
    @Published var previewPNG: Data?
    @Published var failure: StudioFailure?
    @Published private(set) var keptFrames: [String: Data] = [:]

    private let renderer: MetalRenderer
    private let keychain: APIKeyStoring
    private let library: CustomPetLibrary
    private var task: Task<Void, Never>?
    private let providerKind = CustomPetProviderKind.openAI

    init(renderer: MetalRenderer, keychain: APIKeyStoring = KeychainAPIKeyStore(), library: CustomPetLibrary = .shared) {
        self.renderer = renderer
        self.keychain = keychain
        self.library = library
        let defaults = UserDefaults.standard
        modelName = defaults.string(forKey: "custom_pet_model") ?? CustomPetProviderSettings.default.model
        baseURL = defaults.string(forKey: "custom_pet_base_url") ?? CustomPetProviderSettings.default.baseURL
        quality = defaults.string(forKey: "custom_pet_quality") ?? CustomPetProviderSettings.default.quality
        if defaults.object(forKey: "custom_pet_include_walk") != nil {
            includeWalkAtlas = defaults.bool(forKey: "custom_pet_include_walk")
        }
        refreshKeyStatus()
        library.reload()
    }

    private func reloadLibrary() {
        library.reload()
        objectWillChange.send()
    }

    var pets: [CustomPetRecord] { library.records }

    var settings: CustomPetProviderSettings {
        CustomPetProviderSettings(kind: providerKind, model: modelName, baseURL: baseURL, quality: quality)
    }

    var photosReady: Bool {
        PhotoPreprocessor.isReady((photos, issues))
    }

    func refreshKeyStatus() {
        do {
            let stored = try keychain.load(account: providerKind.rawValue)
            keySaved = !(stored ?? "").isEmpty
            keychainFailed = false
        } catch {
            keySaved = false
            keychainFailed = true
        }
    }

    func saveKeyFromField() {
        let typed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains(where: \.isNewline) else { return }
        do {
            try keychain.save(typed, account: providerKind.rawValue)
            apiKeyDraft = ""
            keySaved = true
            keychainFailed = false
        } catch {
            keychainFailed = true
        }
    }

    func clearKey() {
        do {
            try keychain.delete(account: providerKind.rawValue)
            apiKeyDraft = ""
            keySaved = false
            keychainFailed = false
        } catch {
            keychainFailed = true
        }
    }

    func addPhotos(_ urls: [URL]) {
        var files: [(name: String, data: Data)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = (try? Data(contentsOf: url)) ?? Data()
            files.append((url.lastPathComponent, data))
        }
        let prepared = PhotoPreprocessor.prepare(files)
        photos = prepared.photos
        issues = prepared.issues
        keptFrames = [:]
        previewPNG = nil
        failure = nil
        step = .photos
    }

    func generate(retryFailedOnly: Bool) {
        persistSettings()
        guard photosReady else { return }
        guard let settings = settings.validated() else {
            failure = .settings
            step = .failed
            return
        }
        let key: String
        do {
            key = try resolvedKey()
        } catch {
            failure = .noKey
            step = .failed
            return
        }
        guard let provider = CustomPetProviders.make(
            settings: CustomPetProviderSettings(
                kind: providerKind, model: settings.model, baseURL: settings.baseURL, quality: settings.quality
            ),
            apiKey: key
        ) else {
            failure = .settings
            step = .failed
            return
        }
        let existing = retryFailedOnly ? keptFrames : [:]
        if !retryFailedOnly { keptFrames = [:] }
        let photos = self.photos
        let includeWalk = includeWalkAtlas
        failure = nil
        previewPNG = nil
        step = .generating
        progress = CustomPetProgress(completed: 0, total: CustomPetCost.requestCount(includeWalkAtlas: includeWalk), purpose: "reference")
        task?.cancel()
        task = Task { [weak self] in
            let pipeline = CustomPetPipeline(provider: provider, photos: photos)
            let result = await pipeline.run(includeWalkAtlas: includeWalk, existing: existing) { progress in
                Task { @MainActor in self?.progress = progress }
            }
            await MainActor.run { self?.apply(result) }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func save(defaultName: String) -> Bool {
        guard let previewPNG else { return false }
        let name = CustomPetStore.normalizedName(displayName) ?? CustomPetStore.normalizedName(defaultName) ?? "Pet"
        let id = CustomPetStore.makeID()
        let store = CustomPetStore(directory: SkinManager.customSpritesDir)
        do {
            try store.save(
                id: id,
                displayName: name,
                mainPNG: previewPNG,
                walkPNG: keptWalkPNG,
                provider: providerKind.rawValue,
                model: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            failure = .save
            step = .failed
            return false
        }
        reloadLibrary()
        guard renderer.adoptCustomPet(id: id) else {
            failure = .save
            step = .failed
            return false
        }
        keptFrames = [:]
        keptWalkPNG = nil
        previewPNG = nil
        step = .library
        return true
    }

    func rename(id: String, to name: String) {
        let store = CustomPetStore(directory: SkinManager.customSpritesDir)
        guard (try? store.rename(id: id, displayName: name)) != nil else { return }
        reloadLibrary()
    }

    func delete(id: String) {
        let store = CustomPetStore(directory: SkinManager.customSpritesDir)
        guard (try? store.delete(id: id)) != nil else { return }
        renderer.forgetCustomPet(id: id)
        reloadLibrary()
    }

    func use(id: String) {
        _ = renderer.adoptCustomPet(id: id)
    }

    func backToPhotos() {
        task?.cancel()
        step = photos.isEmpty ? .library : .photos
    }

    private var keptWalkPNG: Data?

    private func apply(_ result: CustomPetPipelineResult) {
        keptFrames = result.frames
        keptWalkPNG = result.walkPNG
        progress = CustomPetProgress(
            completed: result.frames.count,
            total: max(progress.total, 1),
            purpose: progress.purpose
        )
        if let main = result.mainPNG {
            previewPNG = main
            failure = nil
            step = .preview
            return
        }
        if result.cancelled {
            failure = .cancelled
        } else if result.failures.values.contains("moderation") {
            failure = .moderation
        } else if !result.failures.isEmpty, result.failures.values.allSatisfy({ $0 == "network" }) {
            failure = .network
        } else if result.failures.values.contains("provider") {
            failure = .provider
        } else {
            failure = .validation(result.failures.keys.sorted())
        }
        step = .failed
    }

    private func resolvedKey() throws -> String {
        let typed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            guard !typed.contains(where: \.isNewline) else { throw CustomPetStoreError.invalidName }
            try keychain.save(typed, account: providerKind.rawValue)
            apiKeyDraft = ""
            keySaved = true
            return typed
        }
        guard let stored = try keychain.load(account: providerKind.rawValue), !stored.isEmpty else {
            throw CustomPetStoreError.invalidName
        }
        return stored
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(modelName, forKey: "custom_pet_model")
        defaults.set(baseURL, forKey: "custom_pet_base_url")
        defaults.set(quality, forKey: "custom_pet_quality")
        defaults.set(includeWalkAtlas, forKey: "custom_pet_include_walk")
    }
}

enum StudioFailure: Equatable {
    case noKey
    case settings
    case moderation
    case network
    case provider
    case validation([String])
    case save
    case cancelled
}

private struct RenameField: View {
    @State private var text: String
    var onSubmitName: (String) -> Void

    init(initial: String, onSubmitName: @escaping (String) -> Void) {
        _text = State(initialValue: initial)
        self.onSubmitName = onSubmitName
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .onSubmit { onSubmitName(text) }
    }
}

struct CustomPetStudioView: View {
    @EnvironmentObject var lang: LanguageManager
    @StateObject private var model: CustomPetStudioModel
    @State private var pickingPhotos = false
    @State private var pendingDelete: CustomPetRecord?

    init(renderer: MetalRenderer) {
        _model = StateObject(wrappedValue: CustomPetStudioModel(renderer: renderer))
    }

    var body: some View {
        ZStack {
            Color.piaCanvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch model.step {
                        case .library:
                            apiSection
                            librarySection
                        case .photos:
                            apiSection
                            photoSection
                        case .generating:
                            progressSection
                        case .preview:
                            previewSection
                        case .failed:
                            failureSection
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 560, height: 680)
        .colorScheme(.light)
        .tint(Color.piaAccent)
        .fileImporter(isPresented: $pickingPhotos, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addPhotos(urls) }
        }
        .confirmationDialog(
            lang["custompet.delete_confirm"],
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(lang["custompet.delete"], role: .destructive) {
                if let pendingDelete { model.delete(id: pendingDelete.id) }
                pendingDelete = nil
            }
            Button(lang["custompet.cancel"], role: .cancel) { pendingDelete = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(Color.piaAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang["custompet.title"]).font(.headline).foregroundStyle(Color.piaInk)
                Text(lang["custompet.subtitle"]).font(.caption).foregroundStyle(Color.piaMuted)
            }
            Spacer()
            if model.step != .library {
                Button(lang["custompet.back"]) { model.backToPhotos() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang["custompet.api_key"]).font(.caption.weight(.semibold)).foregroundStyle(Color.piaMuted)
            SecureField(lang["custompet.api_key_placeholder"], text: $model.apiKeyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(lang["custompet.api_key_save"]) { model.saveKeyFromField() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.keySaved {
                    Button(lang["custompet.api_key_clear"]) { model.clearKey() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
            }
            if model.keySaved {
                Text(lang["custompet.api_key_saved"]).font(.caption).foregroundStyle(Color.piaAccent)
            } else {
                Text(lang["custompet.api_key_missing"]).font(.caption).foregroundStyle(Color.piaMuted)
            }
            if model.keychainFailed {
                Text(lang["custompet.api_key_error"]).font(.caption).foregroundStyle(.red)
            }
            TextField(lang["custompet.model"], text: $model.modelName).textFieldStyle(.roundedBorder)
            TextField(lang["custompet.base_url"], text: $model.baseURL).textFieldStyle(.roundedBorder)
            Picker(lang["custompet.quality"], selection: $model.quality) {
                Text(lang["custompet.quality.low"]).tag("low")
                Text(lang["custompet.quality.medium"]).tag("medium")
                Text(lang["custompet.quality.high"]).tag("high")
            }
            .pickerStyle(.segmented)
            Text(lang["custompet.privacy"]).font(.caption2).foregroundStyle(Color.piaMuted)
        }
        .companionPanel()
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang["custompet.your_pets"]).font(.caption.weight(.semibold)).foregroundStyle(Color.piaMuted)
            if model.pets.isEmpty {
                Text(lang["custompet.empty"]).font(.callout).foregroundStyle(Color.piaMuted)
            }
            ForEach(model.pets) { pet in
                petRow(pet)
            }
            Button { pickingPhotos = true } label: {
                Label(lang["custompet.choose_photos"], systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.piaAccent)
        }
        .companionPanel()
    }

    private func petRow(_ pet: CustomPetRecord) -> some View {
        HStack(spacing: 10) {
            if let image = idleSprite(skinID: pet.id, size: 36) {
                Image(nsImage: image).interpolation(.none).frame(width: 36, height: 36)
            }
            RenameField(initial: pet.displayName) { model.rename(id: pet.id, to: $0) }
            Button(lang["custompet.use"]) { model.use(id: pet.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(role: .destructive) { pendingDelete = pet } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang["custompet.photo_hint"]).font(.callout).foregroundStyle(Color.piaInk)
            Text(lang["custompet.quadruped_note"]).font(.caption).foregroundStyle(Color.piaMuted)
            if !model.photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.photos) { photo in
                        if let image = NSImage(data: photo.pngData) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipped()
                                .cornerRadius(8)
                        }
                    }
                }
            }
            ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                Text(photoIssueText(issue)).font(.caption).foregroundStyle(.red)
            }
            TextField(lang["custompet.name"], text: $model.displayName).textFieldStyle(.roundedBorder)
            Toggle(lang["custompet.include_walk"], isOn: $model.includeWalkAtlas)
                .font(.callout)
            Text(lang.format(
                "custompet.cost_estimate",
                CustomPetCost.estimatedUSD(includeWalkAtlas: model.includeWalkAtlas, quality: model.quality),
                CustomPetCost.requestCount(includeWalkAtlas: model.includeWalkAtlas)
            ))
            .font(.caption)
            .foregroundStyle(Color.piaMuted)
            HStack {
                Button(lang["custompet.choose_photos"]) { pickingPhotos = true }
                    .buttonStyle(.bordered)
                Spacer()
                Button(lang["custompet.generate"]) { model.generate(retryFailedOnly: false) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.piaAccent)
                    .disabled(!model.photosReady)
            }
        }
        .companionPanel()
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: model.progress.total == 0 ? 0 : Double(model.progress.completed) / Double(model.progress.total))
            Text(model.progress.purpose == "reference"
                 ? lang["custompet.progress.reference"]
                 : lang.format("custompet.progress.frame", model.progress.completed, model.progress.total))
                .font(.callout)
            Button(lang["custompet.cancel"]) { model.cancel() }
                .buttonStyle(.bordered)
        }
        .companionPanel()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang["custompet.preview"]).font(.headline)
            if let previewPNG = model.previewPNG, let image = NSImage(data: previewPNG) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.piaWash, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button(lang["custompet.start_over"]) { model.generate(retryFailedOnly: false) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(lang["custompet.save"]) { _ = model.save(defaultName: lang["custompet.default_name"]) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.piaAccent)
            }
        }
        .companionPanel()
    }

    private var failureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(failureText).font(.callout).foregroundStyle(Color.piaInk)
            HStack {
                Button(lang["custompet.back"]) { model.backToPhotos() }.buttonStyle(.bordered)
                Spacer()
                if case .validation = model.failure {
                    Button(lang["custompet.retry_failed"]) { model.generate(retryFailedOnly: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.piaAccent)
                } else if canRetry {
                    Button(lang["custompet.retry_failed"]) { model.generate(retryFailedOnly: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.piaAccent)
                }
            }
        }
        .companionPanel()
    }

    private var canRetry: Bool {
        switch model.failure {
        case .network, .provider, .cancelled, .save:
            return true
        default:
            return false
        }
    }

    private var failureText: String {
        switch model.failure {
        case .noKey: return lang["custompet.error.no_key"]
        case .settings: return lang["custompet.error.settings"]
        case .moderation: return lang["custompet.error.moderation"]
        case .network: return lang["custompet.error.network"]
        case .provider: return lang["custompet.error.provider"]
        case .validation(let frames):
            return lang.format("custompet.error.validation", frames.joined(separator: ", "))
        case .save: return lang["custompet.error.save"]
        case .cancelled: return lang["custompet.error.cancelled"]
        case nil: return lang["custompet.error.provider"]
        }
    }

    private func photoIssueText(_ issue: PhotoPrepIssue) -> String {
        switch issue {
        case .tooFew(let selected, let minimum):
            return lang.format("custompet.issue.too_few", minimum, selected)
        case .tooMany(let selected, let maximum):
            return lang.format("custompet.issue.too_many", maximum, selected)
        case .unreadable(let name):
            return "\(name): \(lang["custompet.issue.unreadable"])"
        case .unsupported(let name):
            return "\(name): \(lang["custompet.issue.unsupported"])"
        case .tooLarge(let name):
            return "\(name): \(lang["custompet.issue.too_large"])"
        case .tooSmall(let name, let shortest, let minimum):
            return "\(name): \(lang.format("custompet.issue.too_small", minimum, shortest))"
        case .extremeAspect(let name):
            return "\(name): \(lang["custompet.issue.aspect"])"
        case .tooBlurry(let name):
            return "\(name): \(lang["custompet.issue.blurry"])"
        case .mostlyEmpty(let name):
            return "\(name): \(lang["custompet.issue.empty"])"
        }
    }
}

final class CustomPetWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        backgroundColor = NSColor.piaCanvas
        isReleasedWhenClosed = false
        level = .floating
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class CustomPetWindowController {
    private let window = CustomPetWindow()

    init(renderer: MetalRenderer, langManager: LanguageManager) {
        let view = CustomPetStudioView(renderer: renderer).environmentObject(langManager)
        window.contentView = NSHostingView(rootView: view)
        window.title = langManager["custompet.title"]
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
