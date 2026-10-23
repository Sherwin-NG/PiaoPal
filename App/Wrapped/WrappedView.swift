import SwiftUI
import AppKit

// MARK: – Count-up animation

private final class CountUpController: ObservableObject {
    @Published var value: Double = 0
    private var timer: Timer?

    func start(to target: Double, duration: Double = 1.2) {
        timer?.invalidate()
        value = 0
        guard target > 0 else { return }
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60.0, repeats: true) { [weak self] t in
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= duration {
                self?.value = target
                t.invalidate()
                return
            }
            self?.value = target * (1 - pow(1 - elapsed / duration, 3))
        }
    }

    func stop() { timer?.invalidate(); timer = nil; value = 0 }
    deinit { timer?.invalidate() }
}

// MARK: – Wrapped view

struct WrappedView: View {
    @EnvironmentObject var lang: LanguageManager
    let stats: CatStats
    let skinID: String
    let onClose: () -> Void

    @AppStorage("pet_name") private var petName: String = ""
    @StateObject private var counter = CountUpController()
    @State private var slide = 0
    @State private var catPulse = false

    private let W: CGFloat = 520
    private let H: CGFloat = 480
    private let total = 6

    private let bgColors: [Color] = [
        .piaCanvas, .piaWash, .piaCanvas, .piaWash, .piaCanvas, .piaWash,
    ]

    var body: some View {
        ZStack {
            bgColors[min(slide, bgColors.count - 1)]
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: slide)

            ZStack {
                introSlide   .offset(y: CGFloat(0 - slide) * H)
                distanceSlide.offset(y: CGFloat(1 - slide) * H)
                napsSlide    .offset(y: CGFloat(2 - slide) * H)
                scratchSlide .offset(y: CGFloat(3 - slide) * H)
                daysSlide    .offset(y: CGFloat(4 - slide) * H)
                outroSlide   .offset(y: CGFloat(5 - slide) * H)
            }
            .frame(width: W, height: H)
            .clipped()

            VStack {
                Spacer()
                progressDots.padding(.bottom, 22)
            }
        }
        .frame(width: W, height: H)
        .colorScheme(.light)
        .contentShape(Rectangle())
        .onTapGesture { guard slide < total - 1 else { return }; advance() }
        .onChange(of: slide, perform: { newSlide in
            counter.stop()
            let targets: [Double] = [
                0,
                stats.distanceMeters,
                Double(stats.naps),
                Double(stats.scratches),
                Double(stats.daysTogether),
                0,
            ]
            let t = targets[newSlide]
            guard t > 0 else { return }
            counter.start(to: t)
        })
    }

    private func advance() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            slide = min(slide + 1, total - 1)
        }
    }

    // MARK: – Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == slide ? Color.piaInk : Color.piaInk.opacity(0.25))
                    .frame(width: i == slide ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: slide)
            }
        }
    }

    // MARK: – Slide 0 · Intro

    private var introSlide: some View {
        VStack(spacing: 0) {
            Spacer()
            Group {
                if let img = sprite(size: 88) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .frame(width: 88, height: 88)
                        .scaleEffect(catPulse ? 1.07 : 1.0)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                                   value: catPulse)
                        .onAppear { catPulse = true }
                }
            }.frame(height: 100)

            Spacer().frame(height: 16)

            Text(lang["wrapped.intro.eyebrow"])
                .font(.system(.caption, design: .default).weight(.heavy))
                .tracking(3)
                .foregroundStyle(Color.piaAccent)

            Spacer().frame(height: 12)

            Text(lang["wrapped.intro.title"])
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundStyle(Color.piaMuted)

            Text(lang.petDisplayName(petName, skinID: skinID))
                .font(.system(size: 46, weight: .black, design: .default))
                .foregroundStyle(Color.piaInk)

            Spacer()

            Text(lang["wrapped.tap_hint"])
                .font(.caption)
                .foregroundStyle(Color.piaMuted)
                .padding(.bottom, 52)
        }
        .frame(width: W)
    }

    // MARK: – Slide 1 · Distance

    private var distanceSlide: some View {
        let m = counter.value
        let display: String = stats.distanceMeters >= 1_000
            ? lang.format("distance.kilometers", m / 1_000)
            : lang.format("distance.meters", m)
        return statSlide(
            eyebrow: lang["wrapped.distance.label"],
            value:   display,
            phrase:  lang["wrapped.distance.phrase.\(distanceTier(stats.distanceMeters))"]
        )
    }

    // MARK: – Slide 2 · Naps

    private var napsSlide: some View {
        statSlide(
            eyebrow: lang["wrapped.naps.label"],
            value:   String(Int(counter.value)),
            phrase:  lang["wrapped.naps.phrase.\(napsTier(stats.naps))"]
        )
    }

    // MARK: – Slide 3 · Scratches

    private var scratchSlide: some View {
        statSlide(
            eyebrow: lang["wrapped.scratches.label"],
            value:   String(Int(counter.value)),
            phrase:  lang["wrapped.scratches.phrase.\(scratchTier(stats.scratches))"]
        )
    }

    // MARK: – Slide 4 · Days

    private var daysSlide: some View {
        statSlide(
            eyebrow: lang["wrapped.days.label"],
            value:   String(Int(counter.value)),
            phrase:  lang["wrapped.days.phrase.\(daysTier(stats.daysTogether))"]
        )
    }

    // MARK: – Slide 5 · Outro

    private var outroSlide: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle().fill(Color.piaAccent.opacity(0.08)).frame(width: 160, height: 160)
                Circle().fill(Color.piaAccent.opacity(0.12)).frame(width: 116, height: 116)
                if let img = sprite(size: 80) {
                    Image(nsImage: img).interpolation(.none).frame(width: 80, height: 80)
                }
            }

            Spacer().frame(height: 28)

            Text(lang["wrapped.outro.title"])
                .font(.system(size: 36, weight: .black, design: .default))
                .foregroundStyle(Color.piaInk)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text(lang["wrapped.outro.sub"])
                .font(.callout)
                .foregroundStyle(Color.piaMuted)

            Spacer().frame(height: 32)

            Button { onClose() } label: {
                Text(lang["wrapped.close"])
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.piaInk)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(Color.piaInk.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.piaInk.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
            Color.clear.frame(height: 44)
        }
        .frame(width: W)
    }

    // MARK: – Shared stat slide template

    private func statSlide(eyebrow: String, value: String, phrase: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Text(eyebrow)
                .font(.system(.caption, design: .default).weight(.heavy))
                .tracking(3)
                .foregroundStyle(Color.piaMuted)

            Spacer().frame(height: 12)

            Text(value)
                .font(.system(size: 76, weight: .black, design: .default))
                .foregroundStyle(Color.piaInk)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 32)
                .contentTransition(.numericText())

            Spacer().frame(height: 28)

            Text(phrase)
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundStyle(Color.piaInk.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 52)

            Spacer()
            Color.clear.frame(height: 44)
        }
        .frame(width: W)
    }

    // MARK: – Tier helpers

    private func distanceTier(_ m: Double) -> Int {
        switch m {
        case ..<100:      return 0
        case ..<1_000:    return 1
        case ..<10_000:   return 2
        case ..<100_000:  return 3
        default:          return 4
        }
    }

    private func napsTier(_ n: Int) -> Int {
        switch n {
        case ..<5:   return 0
        case ..<20:  return 1
        case ..<100: return 2
        default:     return 3
        }
    }

    private func scratchTier(_ n: Int) -> Int {
        switch n {
        case ..<5:   return 0
        case ..<20:  return 1
        case ..<100: return 2
        default:     return 3
        }
    }

    private func daysTier(_ d: Int) -> Int {
        switch d {
        case ..<7:   return 0
        case ..<30:  return 1
        case ..<100: return 2
        case ..<365: return 3
        default:     return 4
        }
    }

    // MARK: – Sprite loader

    private func sprite(size: CGFloat) -> NSImage? {
        idleSprite(skinID: skinID, size: size)
    }
}
