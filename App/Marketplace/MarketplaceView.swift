import SwiftUI
import AppKit

// MARK: – Data models

struct MarketplaceSkin: Decodable, Identifiable {
    let id: String
    let name: String
    let author: String
    let bundled: Bool
    let url: String?
}

private struct MarketplaceManifest: Decodable {
    let sprites: [MarketplaceSkin]
}

// MARK: – Store

@MainActor
final class MarketplaceStore: ObservableObject {
    @Published private(set) var skins: [MarketplaceSkin] = []
    @Published private(set) var downloading: Set<String> = []
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String? = nil

    let renderer: MetalRenderer

    private let manifestURL = URL(string:
        "https://raw.githubusercontent.com/Sherwin-NG/PiaoPal/main/Resources/companion-catalog.json"
    )!

    init(renderer: MetalRenderer) {
        self.renderer = renderer
        if let url = Bundle.main.url(forResource: "companion-catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let manifest = try? JSONDecoder().decode(MarketplaceManifest.self, from: data) {
            skins = manifest.sprites
        }
    }

    func fetchManifest() async {
        isLoading = true
        loadError = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: manifestURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let manifest  = try JSONDecoder().decode(MarketplaceManifest.self, from: data)
            skins = manifest.sprites
        } catch {
            Log.store.error("Skin marketplace load failed: \(error.localizedDescription, privacy: .private)")
            loadError = "marketplace.error_detail"
        }
        isLoading = false
    }

    func download(_ skin: MarketplaceSkin) {
        guard let urlString = skin.url, let url = URL(string: urlString) else { return }
        downloading.insert(skin.id)
        failed.remove(skin.id)
        renderer.skinManager.downloadSprite(id: skin.id, from: url) { [weak self] success in
            guard let self else { return }
            self.downloading.remove(skin.id)
            if success {
                self.renderer.refreshAvailableSkins()
            } else {
                self.failed.insert(skin.id)
            }
        }
    }

    func isInstalled(_ id: String) -> Bool {
        renderer.skinManager.texture(id: id) != nil
    }
}

// MARK: – Main view

struct MarketplaceView: View {
    @EnvironmentObject var lang: LanguageManager
    @ObservedObject var store: MarketplaceStore

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color.piaCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)

                if store.isLoading && store.skins.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(lang["marketplace.loading"])
                            .font(.callout)
                            .foregroundStyle(Color.piaMuted)
                    }
                    Spacer()
                } else if let err = store.loadError, store.skins.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.piaAccent)
                        Text(lang["marketplace.error"])
                            .font(.headline)
                            .foregroundStyle(Color.piaInk)
                        Text(lang[err])
                            .font(.caption)
                            .foregroundStyle(Color.piaMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button(lang["marketplace.retry"]) {
                            Task { await store.fetchManifest() }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.piaAccent)
                    }
                    Spacer()
                } else {
                    if store.loadError != nil {
                        HStack(spacing: 10) {
                            Text(lang["marketplace.local"]).font(.caption).foregroundStyle(Color.piaMuted)
                            Spacer()
                            Button(lang["marketplace.retry"]) { Task { await store.fetchManifest() } }
                                .buttonStyle(.bordered).controlSize(.small).disabled(store.isLoading)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                    }
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.skins) { skin in
                                skinCard(skin)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .frame(width: 460, height: 420)
        .colorScheme(.light)
        .tint(Color.piaAccent)
        .task { await store.fetchManifest() }
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(Color.piaAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang["marketplace.title"])
                    .font(.headline)
                    .foregroundStyle(Color.piaInk)
                Text(lang["marketplace.subtitle"])
                    .font(.caption)
                    .foregroundStyle(Color.piaMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: – Skin card

    private func skinCard(_ skin: MarketplaceSkin) -> some View {
        let installed  = store.isInstalled(skin.id)
        let inProgress = store.downloading.contains(skin.id)
        let hasFailed  = store.failed.contains(skin.id)

        return VStack(spacing: 8) {
            // Preview sprite
            ZStack {
                Circle()
                    .fill(Color.piaAccent.opacity(0.1))
                    .frame(width: 72, height: 72)
                if let img = spritePreview(for: skin.id) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .frame(width: 52, height: 52)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.title2)
                        .foregroundStyle(Color.piaMuted)
                }
            }

            Text(skin.bundled ? lang.skinName(for: skin.id) : skin.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.piaInk)

            Text(skin.bundled ? lang[skin.id == "piaopiao" ? "marketplace.credit.piaopiao" : "marketplace.credit.original"] : "@\(skin.author)")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.piaMuted)

            // Status / action
            if skin.bundled || installed {
                Text(skin.bundled ? lang["marketplace.bundled"] : lang["marketplace.installed"])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            } else if inProgress {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(height: 22)
            } else {
                Button {
                    store.download(skin)
                } label: {
                    Text(hasFailed ? "↺" : lang["marketplace.download"])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.piaAccent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.piaInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.piaInk.opacity(0.08), lineWidth: 1))
    }

    // MARK: – Sprite preview (idle frame)

    private func spritePreview(for id: String) -> NSImage? {
        idleSprite(skinID: id, size: 52)
    }
}
