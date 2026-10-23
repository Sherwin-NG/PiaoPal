import SwiftUI
import AppKit
import ServiceManagement

// MARK: – Section label

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color.piaAccent.opacity(0.75))
    }
}

// MARK: – Speed segmented control

private struct SpeedControl: View {
    @EnvironmentObject var lang: LanguageManager
    @Binding var value: Float
    private let opts: [(String, Float, String)] = [
        ("tortoise.fill", 0.4, "speed.slow"),
        ("pawprint.fill", 1.0, "speed.normal"),
        ("bolt.fill", 2.5, "speed.fast"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opts, id: \.1) { symbol, v, labelKey in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { value = v }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(abs(value - v) < 0.01
                                      ? Color.piaAccent.opacity(0.25)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(lang[labelKey])
                .accessibilityLabel(lang[labelKey])
            }
        }
        .padding(3)
        .background(Color.piaSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.piaBorder, lineWidth: 1))
    }
}

// MARK: – XP bar

private struct XPBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.piaInk.opacity(0.08))
                Capsule()
                    .fill(Color.piaAccent)
                    .frame(width: max(6, g.size.width * CGFloat(progress)))
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: – Stat card

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: icon).foregroundStyle(Color.piaAccent)
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(Color.piaInk)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.piaMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.piaSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.piaBorder, lineWidth: 1))
    }
}

// MARK: – Achievement pill

private struct AchievementPill: View {
    @EnvironmentObject var lang: LanguageManager
    let achievement: Achievement
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: achievement.icon)
                .font(.title3)
                .opacity(unlocked ? 1 : 0.22)
            Text(achievement.localizedTitle(using: lang))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(unlocked ? Color.piaInk.opacity(0.85) : Color.piaMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 58, height: 54)
        .background(
            unlocked ? Color.piaAccent.opacity(0.12) : Color.piaInk.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    unlocked ? Color.piaAccent.opacity(0.28) : Color.piaInk.opacity(0.05),
                    lineWidth: 1
                )
        )
    }
}

// MARK: – Skin preview

struct SkinPreview: View {
    @EnvironmentObject var lang: LanguageManager
    let skinID: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.piaAccent.opacity(0.18) : Color.piaInk.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.piaAccent : Color.piaInk.opacity(0.1),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .frame(width: 56, height: 56)

                if let img = idleImage(for: skinID) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .frame(width: 48, height: 48)
                }
            }
            Text(lang.skinName(for: skinID))
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.piaInk : Color.piaMuted)
        }
    }

    private func idleImage(for id: String) -> NSImage? {
        idleSprite(skinID: id, size: 48)
    }
}

// MARK: – Main settings view

struct SettingsView: View {
    @ObservedObject var renderer: MetalRenderer
    @ObservedObject var updater: Updater
    @EnvironmentObject var lang: LanguageManager
    let onShowWrapped: () -> Void
    let onShowMarketplace: () -> Void
    let onShowAchievements: () -> Void

    @AppStorage("pet_name") private var petName: String = ""
    @State private var eggTaps = 0
    @State private var showEgg = false
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    private var catStats: CatStats { renderer.catStats }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        petSection.companionPanel().frame(width: 292)
                        VStack(alignment: .leading, spacing: 16) {
                            statsSection.companionPanel()
                            achievementsSection.companionPanel()
                            wrappedButton
                        }
                        .frame(maxWidth: .infinity)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        personalizeSection.companionPanel().frame(width: 292)
                        updatesSection.companionPanel().frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            bottomBar
        }
        .frame(width: 680, height: 630)
        .foregroundStyle(Color.piaInk)
        .background(Color.piaCanvas)
        .tint(Color.piaAccent)
        .colorScheme(.light)
    }

    // MARK: – Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundStyle(Color.piaAccent)
                .onTapGesture { handleEggTap() }
                .popover(isPresented: $showEgg, arrowEdge: .trailing) { eggPopover }

            VStack(alignment: .leading, spacing: 4) {
                Text(lang.appName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.piaInk)
                Text("PiaoPal · \(updater.currentVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.piaMuted)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                Text(lang.format("stats.level", catStats.level))
                    .font(.caption.bold())
                    .foregroundStyle(Color.piaInk)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.piaAccent.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.piaAccent.opacity(0.35), lineWidth: 1))

            Text(String(format: "%.0f fps", renderer.stats.fps))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.piaMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.piaInk.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.piaInk.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func handleEggTap() {
        eggTaps += 1
        if eggTaps >= 5 {
            eggTaps = 0
            showEgg = true
            renderer.achievementManager.triggerEasterEgg()
        }
    }

    private var eggPopover: some View {
        VStack(spacing: 10) {
            Image(systemName: "pawprint.fill").font(.title).foregroundStyle(Color.piaAccent)
            Text(lang.appName).font(.headline)
            Divider()
            Link("Sherwin-NG", destination: URL(string: "https://github.com/Sherwin-NG")!)
                .font(.subheadline.weight(.semibold))
            Text(lang["brand.piaopiao_credit"]).font(.caption).foregroundStyle(.secondary)
            Text(lang["brand.original_credit"]).font(.caption).foregroundStyle(.secondary)
            Link("@hellov3an", destination: URL(string: "https://github.com/hellov3an")!)
                .font(.subheadline.weight(.semibold))
            if let credits = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                Link(lang["brand.credits"], destination: credits).font(.caption)
            }
            if let license = Bundle.main.url(forResource: "LICENSE", withExtension: nil) {
                Link(lang["brand.license"], destination: license).font(.caption)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    // MARK: – Pet section (skin + size + speed)

    private var petSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: lang["settings.your_pet"])

            HStack(spacing: 12) {
                if let image = idleSprite(skinID: renderer.currentSkinID, size: 64) {
                    Image(nsImage: image).interpolation(.none).frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 5) {
                    TextField(lang.skinName(for: renderer.currentSkinID), text: $petName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 21, weight: .semibold))
                        .accessibilityLabel(lang["ob.name.title"])
                    Text(lang.skinName(for: renderer.currentSkinID))
                        .font(.caption).foregroundStyle(Color.piaMuted)
                }
            }
            .padding(.vertical, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(renderer.allSkinIDs, id: \.self) { id in
                    Button { renderer.setSkin(id) } label: {
                        SkinPreview(skinID: id, isSelected: renderer.currentSkinID == id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lang.skinName(for: id))
                }
            }
            Divider().padding(.vertical, 4)

            Button { onShowMarketplace() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill").font(.caption).foregroundStyle(Color.piaAccent)
                    Text(lang["settings.marketplace"]).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.piaInk.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.piaInk.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                Text(lang["settings.size"]).font(.callout).foregroundStyle(Color.piaInk)
                Slider(
                    value: Binding(
                        get: { Double(renderer.catScale) },
                        set: { renderer.setCatScale(Float($0)) }
                    ),
                    in: 0.5...3.0, step: 0.25
                )
                Text(String(format: "%.2g×", renderer.catScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.piaMuted)
                    .frame(width: 30, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text(lang["settings.speed"]).font(.callout).foregroundStyle(Color.piaInk)
                Spacer()
                SpeedControl(value: Binding(
                    get: { renderer.speedMultiplier },
                    set: { renderer.setSpeedMultiplier($0) }
                ))
                .frame(width: 116)
            }
        }
    }

    // MARK: – Stats section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: lang["settings.stats"])

            HStack(spacing: 10) {
                StatCard(
                    icon: "calendar",
                    value: "\(catStats.streak)",
                    label: lang["stats.day_streak"]
                )
                StatCard(
                    icon: "star.fill",
                    value: lang.format("stats.level", catStats.level),
                    label: lang.format("stats.xp_progress", Int(catStats.distanceMeters), Int(catStats.distanceMeters + catStats.metersToNextLevel))
                )
            }

            VStack(spacing: 5) {
                XPBar(progress: catStats.xpProgress)
                HStack {
                    Text(lang.format("stats.walked_distance", Int(catStats.distanceMeters)))
                        .font(.caption2)
                        .foregroundStyle(Color.piaMuted)
                    Spacer()
                    Text(lang.format("stats.next_level", catStats.metersToNextLevel, catStats.level + 1))
                        .font(.caption2)
                        .foregroundStyle(Color.piaMuted)
                }
            }
        }
    }

    // MARK: – Achievements section

    private var achievementsSection: some View {
        let manager = renderer.achievementManager
        let total   = allAchievements.count
        let count   = manager.unlockedIDs.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: lang["settings.achievements"])
                Spacer()
                Text("\(count)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(count == total ? Color.piaAccent : Color.piaMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allAchievements.prefix(8)) { a in
                        AchievementPill(
                            achievement: a,
                            unlocked: manager.unlockedIDs.contains(a.id)
                        )
                        .help(manager.unlockedIDs.contains(a.id)
                              ? "\(a.localizedTitle(using: lang)) — \(a.localizedDescription(using: lang))"
                              : "???")
                    }
                }
                .padding(.vertical, 2)
            }

            Button { onShowAchievements() } label: {
                HStack {
                    Text(lang["achievements.viewAll"])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.piaAccent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.piaAccent.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.piaAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.piaAccent.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: – Wrapped CTA

    private var wrappedButton: some View {
        Button { onShowWrapped() } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text(lang["wrapped.btn"])
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.piaInk)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                Color.piaWash,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Personalize section

    private var personalizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: lang["settings.personalize"])

            Toggle(lang["settings.launch_login"], isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)
                .onChange(of: launchAtLogin) { newVal in
                    do {
                        if newVal { try SMAppService.mainApp.register() }
                        else      { try SMAppService.mainApp.unregister() }
                    } catch { launchAtLogin = !newVal }
                }

            Button { shareCardFromSettings() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                    Text(lang["ob.card.share"]).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.piaInk.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.piaInk.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func shareCardFromSettings() {
        let name = lang.petDisplayName(petName, skinID: renderer.currentSkinID)
        let skinID = renderer.currentSkinID
        let dateStr: String = {
            if let stored = UserDefaults.standard.string(forKey: "adoption_date"),
               let date = ISO8601DateFormatter().date(from: stored) {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.locale = Locale(identifier: lang.language.rawValue)
                return fmt.string(from: date)
            }
            let fmt = DateFormatter(); fmt.dateStyle = .medium
            fmt.locale = Locale(identifier: lang.language.rawValue)
            return fmt.string(from: Date())
        }()
        let exportView = CardExportView(
            name: name, skinID: skinID, skinName: lang.skinName(for: skinID), dateStr: dateStr,
            personality: lang.personality(for: skinID),
            adoptedLabel: lang["ob.card.adopted"],
            personalityLabel: lang["ob.card.personality"],
            skinLabel: lang["settings.skin"]
        )
        guard let image = renderCard(exportView: exportView) else { return }
        showSharePicker(for: image)
    }

    // MARK: – Updates section

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: lang["settings.updates"])

            HStack(spacing: 10) {
                updateStatusView
                Spacer()
                Button(lang["settings.check_btn"]) {
                    Task { await updater.checkForUpdates() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled({
                    switch updater.state {
                    case .checking: return true
                    default: return false
                    }
                }())
            }

            if case .available(let version, let url) = updater.state {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                    Text("v\(version) \(lang["update.available"])").fontWeight(.medium)
                    Spacer()
                    Button(lang["update.install_btn"]) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updater.state {
        case .idle:
            Text(lang["update.never"]).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text(lang["update.checking"]) }
        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(lang["update.up_to_date"])
            }
        case .available(let v, _):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.piaAccent)
                Text("v\(v) \(lang["update.available"])")
            }
        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(lang[msg]).foregroundStyle(.red)
            }
        }
    }

    // MARK: – Bottom bar

    private var bottomBar: some View {
        HStack {
            Button { showEgg = true } label: {
                Image(systemName: "info.circle").font(.callout)
            }
            .buttonStyle(.plain)
            .help(lang["brand.name"])
            Link("GitHub", destination: URL(string: "https://github.com/Sherwin-NG/PiaoPal")!)
                .font(.caption)
                .foregroundStyle(Color.piaMuted)
            Spacer()
            languagePicker
            Spacer()
            Button(lang["settings.quit"]) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.piaInk.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var languagePicker: some View {
        Picker("", selection: Binding(
            get: { lang.language },
            set: { lang.set($0) }
        )) {
            ForEach(Language.allCases) { l in
                Text("\(l.flag) \(l.displayName)").tag(l)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 142)
        .controlSize(.small)
    }
}
