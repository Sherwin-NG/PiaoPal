import SwiftUI
import AppKit

// MARK: – Onboarding host (5-step sliding wizard)

struct OnboardingView: View {
    @EnvironmentObject var lang: LanguageManager
    let renderer: MetalRenderer
    let onFinish: () -> Void

    @AppStorage("pet_name") private var petName: String = ""
    @State private var step = 0
    @State private var selectedSkin: String
    @State private var catPulse = false

    private let windowW: CGFloat = 520
    private let stepCount = 5

    init(renderer: MetalRenderer, onFinish: @escaping () -> Void) {
        self.renderer = renderer
        self.onFinish = onFinish
        self._selectedSkin = State(initialValue: renderer.currentSkinID)
    }

    private let stepKeys = ["nav.language", "nav.meet", "nav.companion", "nav.name", "nav.card"]
    private let stepIcons = ["globe", "pawprint.fill", "square.grid.2x2.fill", "pencil", "person.crop.rectangle"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .padding(.bottom, 12)
                Text(lang.appName).font(.system(size: 28, weight: .semibold))
                Text("PiaoPal").font(.caption.monospaced()).foregroundStyle(Color.piaMuted)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        HStack(spacing: 10) {
                            Image(systemName: index < step ? "checkmark.circle.fill" : stepIcons[index])
                                .frame(width: 20)
                            Text(lang[stepKeys[index]])
                                .font(.system(size: 12, weight: step == index ? .semibold : .regular))
                        }
                        .foregroundStyle(step == index ? Color.piaAccent : Color.piaMuted)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(step == index ? Color.piaSurface : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 32)
                Spacer()
                Text(String(format: "%02d / 05", step + 1))
                    .font(.caption.monospaced()).foregroundStyle(Color.piaMuted)
            }
            .padding(24)
            .frame(width: 200)
            .background(Color.piaWash)
            VStack(spacing: 0) {
                stepsContainer
                Divider()
                navBar
            }
            .frame(width: windowW)
        }
        .frame(width: 720, height: 540)
        .foregroundStyle(Color.piaInk)
        .background(Color.piaCanvas)
        .tint(Color.piaAccent)
        .colorScheme(.light)
    }

    @ViewBuilder
    private var stepsContainer: some View {
        Group {
            switch step {
            case 0: languageStep
            case 1: conceptStep
            case 2: catStep
            case 3: nameStep
            default: welcomeStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .id(step)
    }

    // MARK: – Step 0 · Concept

    private var conceptStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                if let img = loadSprite(skinID: SkinManager.defaultSkinID, size: 88) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .frame(width: 88, height: 88)
                        .scaleEffect(catPulse ? 1.06 : 1.0)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                                   value: catPulse)
                        .onAppear { catPulse = true }
                }
            }
            .frame(height: 100)

            Spacer().frame(height: 4)

            Text(lang["ob.concept.eyebrow"].uppercased())
                .font(.caption)
                .tracking(2)
                .foregroundStyle(Color.piaMuted)

            Spacer().frame(height: 10)

            Text(lang["ob.concept.title"])
                .font(.system(size: 28, weight: .bold, design: .default))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.piaInk)

            Spacer().frame(height: 28)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "cursorarrow.motionlines",      text: lang["ob.concept.f1"])
                featureRow(icon: "moon.zzz.fill",               text: lang["ob.concept.f2"])
                featureRow(icon: "rectangle.on.rectangle.fill", text: lang["ob.concept.f3"])
            }
            .frame(maxWidth: 300)

            Spacer()
        }
        .frame(width: windowW)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.piaAccent)
                .frame(width: 22)
            Text(text)
                .foregroundStyle(Color.piaInk.opacity(0.7))
                .font(.callout)
            Spacer()
        }
    }

    // MARK: – Step 1 · Language

    private var languageStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(lang["ob.lang.title"])
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundStyle(Color.piaInk)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 32)

            VStack(spacing: 12) {
                ForEach(Array(stride(from: 0, to: Language.allCases.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 12) {
                        ForEach(Array(Language.allCases.dropFirst(start).prefix(3))) { l in
                            langTile(l)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(width: windowW)
    }

    private func langTile(_ l: Language) -> some View {
        let isSelected = lang.language == l
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { lang.set(l) }
        } label: {
            VStack(spacing: 7) {
                Text(l.flag).font(.system(size: 34))
                Text(l.displayName)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.piaInk : Color.piaMuted)
            }
            .frame(width: 148, height: 82)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.piaWash : Color.piaSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.piaAccent : Color.piaInk.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: lang.language)
    }

    // MARK: – Step 2 · Cat

    private var catStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(lang["ob.cat.title"])
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundStyle(Color.piaInk)

            Spacer().frame(height: 20)

            ZStack {
                Circle()
                    .fill(Color.piaAccent.opacity(0.1))
                    .frame(width: 104, height: 104)

                if let img = loadSprite(skinID: selectedSkin, size: 72) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .frame(width: 72, height: 72)
                        .id(selectedSkin)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            Spacer().frame(height: 20)

            HStack(spacing: 10) {
                ForEach(SkinManager.skinIDs, id: \.self) { id in catTile(id) }
            }

            Spacer().frame(height: 14)

            Text(lang["ob.cat.subtitle"])
                .font(.caption)
                .foregroundStyle(Color.piaMuted)

            Spacer()
        }
        .frame(width: windowW)
    }

    private func catTile(_ id: String) -> some View {
        let isSelected = selectedSkin == id
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                selectedSkin = id
            }
            renderer.setSkin(id)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.piaWash : Color.piaSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.piaAccent : Color.piaInk.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .frame(width: 68, height: 68)

                    if let img = loadSprite(skinID: id, size: 52) {
                        Image(nsImage: img)
                            .interpolation(.none)
                            .frame(width: 52, height: 52)
                    }
                }
                Text(lang.skinName(for: id))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.piaInk : Color.piaMuted)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selectedSkin)
    }

    // MARK: – Step 3 · Name

    private var nameStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.piaAccent.opacity(0.1))
                    .frame(width: 104, height: 104)

                if let img = loadSprite(skinID: selectedSkin, size: 72) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .frame(width: 72, height: 72)
                        .id(selectedSkin)
                }
            }

            Spacer().frame(height: 26)

            Text(lang["ob.name.title"])
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundStyle(Color.piaInk)

            Spacer().frame(height: 22)

            TextField(lang.skinName(for: selectedSkin), text: $petName)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .bold, design: .default))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.piaInk)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.piaInk.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.piaInk.opacity(0.15), lineWidth: 1)
                )
                .frame(maxWidth: 280)

            Spacer().frame(height: 14)

            Text(lang["ob.name.subtitle"])
                .font(.caption)
                .foregroundStyle(Color.piaMuted)

            Spacer()
        }
        .frame(width: windowW)
    }

    // MARK: – Step 4 · ID Card

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(lang["ob.card.eyebrow"])
                .font(.system(.caption2, design: .default).weight(.heavy))
                .tracking(2)
                .foregroundStyle(Color.piaAccent)

            Spacer().frame(height: 16)

            PetCardView(
                name: displayName,
                skinID: selectedSkin,
                skinName: lang.skinName(for: selectedSkin),
                dateStr: adoptionDateDisplay,
                personality: lang.personality(for: selectedSkin),
                adoptedLabel: lang["ob.card.adopted"],
                personalityLabel: lang["ob.card.personality"],
                skinLabel: lang["settings.skin"]
            )

            Spacer().frame(height: 16)

            Button { shareCard() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                    Text(lang["ob.card.share"]).font(.caption.weight(.medium))
                }
                .foregroundStyle(Color.piaInk.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.piaInk.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.piaInk.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: windowW)
    }

    private func shareCard() {
        let exportView = CardExportView(
            name: displayName,
            skinID: selectedSkin,
            skinName: lang.skinName(for: selectedSkin),
            dateStr: adoptionDateDisplay,
            personality: lang.personality(for: selectedSkin),
            adoptedLabel: lang["ob.card.adopted"],
            personalityLabel: lang["ob.card.personality"],
            skinLabel: lang["settings.skin"]
        )
        guard let image = renderCard(exportView: exportView) else { return }
        showSharePicker(for: image)
    }

    private var displayName: String {
        lang.petDisplayName(petName, skinID: selectedSkin)
    }

    private var adoptionDateDisplay: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        fmt.locale = Locale(identifier: lang.language.rawValue)
        return fmt.string(from: Date())
    }

    // MARK: – Navigation bar

    private var navBar: some View {
        HStack(spacing: 0) {
            Group {
                if step > 0 {
                    Button(lang["btn.back"]) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                            step -= 1
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(Color.piaMuted)
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.piaAccent : Color.piaInk.opacity(0.2))
                        .frame(width: i == step ? 22 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
                }
            }

            Spacer()

            Group {
                if step < stepCount - 1 {
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                            step += 1
                        }
                    } label: {
                        nextLabel(lang["btn.next"])
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { onFinish() } label: {
                        nextLabel(lang["btn.start"])
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private func nextLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Color.piaAccent, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: – Helpers

    private func loadSprite(skinID: String, size: CGFloat) -> NSImage? {
        idleSprite(skinID: skinID, size: size)
    }
}
