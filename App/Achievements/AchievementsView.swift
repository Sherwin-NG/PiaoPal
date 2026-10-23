import SwiftUI

// MARK: – Category pill

private struct CategoryPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.piaInk : Color.piaMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    selected ? Color.piaAccent.opacity(0.22) : Color.piaInk.opacity(0.05),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(
                    selected ? Color.piaAccent.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Achievement card

private struct AchievementCard: View {
    @EnvironmentObject var lang: LanguageManager
    let achievement: Achievement
    let unlocked: Bool
    let unlockedAt: Date?

    // Secret + locked → show "???"
    private var revealed: Bool { unlocked || !achievement.isSecret }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: unlocked ? achievement.icon : (achievement.isSecret ? "lock.fill" : achievement.icon))
                .font(.system(size: 30))
                .opacity(unlocked ? 1 : 0.25)
                .padding(.top, 4)

            Text(revealed ? achievement.localizedTitle(using: lang) : "???")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(unlocked ? Color.piaInk : Color.piaMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Group {
                if unlocked, let date = unlockedAt {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year()
                        .locale(Locale(identifier: lang.language.rawValue))))
                        .foregroundStyle(Color.piaAccent.opacity(0.75))
                } else {
                    Text(revealed ? achievement.localizedDescription(using: lang) : lang["achievements.secret"])
                        .foregroundStyle(Color.piaMuted)
                        .lineLimit(2)
                }
            }
            .font(.system(size: 9))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            unlocked ? Color.piaAccent.opacity(0.10) : Color.piaInk.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    unlocked ? Color.piaAccent.opacity(0.28) : Color.piaInk.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}

// MARK: – Main achievements view

struct AchievementsView: View {
    @EnvironmentObject var lang: LanguageManager
    @ObservedObject var manager: AchievementManager
    @State private var filter: AchievementCategory? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var displayed: [Achievement] {
        guard let f = filter else { return allAchievements }
        return allAchievements.filter { $0.category == f }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryBar
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(displayed) { a in
                        AchievementCard(
                            achievement: a,
                            unlocked:    manager.unlockedIDs.contains(a.id),
                            unlockedAt:  manager.unlockedDates[a.id]
                        )
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 420)
        .background(Color.piaCanvas)
        .colorScheme(.light)
    }

    // MARK: – Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang["achievements.title"])
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Color.piaAccent.opacity(0.8))
                    Text(lang.format("achievements.progress", manager.unlockedIDs.count, allAchievements.count))
                        .font(.title3.bold())
                        .foregroundStyle(Color.piaInk)
                }
                Spacer()
                // Trophy ring
                ZStack {
                    Circle()
                        .stroke(Color.piaInk.opacity(0.08), lineWidth: 4)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: CGFloat(manager.unlockedIDs.count) / CGFloat(allAchievements.count))
                        .stroke(
                            Color.piaAccent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: manager.unlockedIDs.count)
                    Image(systemName: "trophy.fill").foregroundStyle(Color.piaAccent)
                        .font(.title3)
                }
            }

            // Progress bar
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.piaInk.opacity(0.07))
                    Capsule()
                        .fill(Color.piaAccent)
                        .frame(width: max(6, g.size.width
                               * CGFloat(manager.unlockedIDs.count)
                               / CGFloat(max(1, allAchievements.count))))
                        .animation(.easeInOut(duration: 0.5), value: manager.unlockedIDs.count)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.piaInk.opacity(0.07)).frame(height: 1)
        }
    }

    // MARK: – Category bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                CategoryPill(label: lang["achievements.all"], selected: filter == nil) { filter = nil }
                ForEach(AchievementCategory.allCases) { cat in
                    CategoryPill(label: cat.localizedLabel(using: lang), selected: filter == cat) { filter = cat }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.piaInk.opacity(0.07)).frame(height: 1)
        }
    }
}
