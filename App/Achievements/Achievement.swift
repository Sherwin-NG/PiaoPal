import Foundation

// MARK: – Category

enum AchievementCategory: String, CaseIterable, Identifiable {
    case explorer, sleeper, chaos, loyal, play, secret
    var id: String { rawValue }

    var label: String {
        switch self {
        case .explorer: "Explorer"
        case .sleeper:  "Sleeper"
        case .chaos:    "Chaos"
        case .loyal:    "Loyal"
        case .play:     "Play"
        case .secret:   "Secret"
        }
    }

    func localizedLabel(using languageManager: LanguageManager) -> String {
        languageManager["achievement.category.\(rawValue)"]
    }
}

// MARK: – Model

struct Achievement: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let category: AchievementCategory
    let isSecret: Bool

    func localizedTitle(using languageManager: LanguageManager) -> String {
        languageManager["achievement.\(id).title"]
    }

    func localizedDescription(using languageManager: LanguageManager) -> String {
        languageManager["achievement.\(id).description"]
    }
}

// MARK: – All 32 achievements

enum AchievementRules {
    // A fresh PiaoPal collection includes all six bundled companions.
    static let bundledSkinIDs: Set<String> = ["piaopiao", "classic", "dog", "tora", "maia", "vaporwave"]

    static func allBundledSkinsUsed(_ usedSkinIDs: Set<String>) -> Bool {
        bundledSkinIDs.isSubset(of: usedSkinIDs)
    }
}

let allAchievements: [Achievement] = [

    // ── Explorer ─────────────────────────────────────────────────────────────
    Achievement(id: "first_step",     icon: "pawprint.fill", title: "First Step",
                description: "Your cat started walking",            category: .explorer, isSecret: false),
    Achievement(id: "hundred_meters", icon: "map.fill", title: "Night Walker",
                description: "Walked 100 meters",                   category: .explorer, isSecret: false),
    Achievement(id: "one_km",         icon: "location.fill", title: "Kilometer Club",
                description: "Walked 1 kilometer",                  category: .explorer, isSecret: false),
    Achievement(id: "ten_km",         icon: "figure.walk", title: "Marathon Cat",
                description: "Walked 10 kilometers",                category: .explorer, isSecret: false),
    Achievement(id: "hundred_km",     icon: "globe", title: "World Tour",
                description: "Walked 100 kilometers",               category: .explorer, isSecret: true),
    Achievement(id: "speed_demon",    icon: "bolt.fill", title: "Speed Demon",
                description: "Activated Hyper speed",               category: .explorer, isSecret: false),
    Achievement(id: "slow_life",      icon: "tortoise.fill", title: "Slow Life",
                description: "Activated Lazy mode",                 category: .explorer, isSecret: false),

    // ── Sleeper ───────────────────────────────────────────────────────────────
    Achievement(id: "nap_10",         icon: "bed.double.fill", title: "Nap Champion",
                description: "10 naps taken",                       category: .sleeper, isSecret: false),
    Achievement(id: "nap_100",        icon: "cloud.moon.fill", title: "Sleepyhead",
                description: "100 naps taken",                      category: .sleeper, isSecret: false),
    Achievement(id: "nap_1000",       icon: "moon.stars.fill", title: "Comatose",
                description: "1000 naps taken",                     category: .sleeper, isSecret: true),
    Achievement(id: "docked_first",   icon: "moon.fill", title: "Up in the Attic",
                description: "Docked to the menu bar",              category: .sleeper, isSecret: false),
    Achievement(id: "docked_long",    icon: "snowflake", title: "Cryogenic",
                description: "Stayed docked for 1 hour straight",   category: .sleeper, isSecret: true),

    // ── Chaos ─────────────────────────────────────────────────────────────────
    Achievement(id: "scratch_10",     icon: "pawprint.fill", title: "Scratcher",
                description: "10 scratches",                        category: .chaos, isSecret: false),
    Achievement(id: "scratch_100",    icon: "bolt.fill", title: "Wall Destroyer",
                description: "100 scratches",                       category: .chaos, isSecret: false),
    Achievement(id: "scratch_1000",   icon: "hammer.fill", title: "Demolition Expert",
                description: "1000 scratches",                      category: .chaos, isSecret: true),
    Achievement(id: "giant_cat",      icon: "arrow.up.left.and.arrow.down.right", title: "Kaiju Cat",
                description: "Set cat size to 3×",                  category: .chaos, isSecret: false),
    Achievement(id: "tiny_cat",       icon: "arrow.down.right.and.arrow.up.left", title: "Quantum Cat",
                description: "Set cat size to 0.5×",               category: .chaos, isSecret: true),

    // ── Loyal ─────────────────────────────────────────────────────────────────
    Achievement(id: "streak_7",       icon: "flame.fill", title: "Loyal",
                description: "7-day streak",                        category: .loyal, isSecret: false),
    Achievement(id: "streak_30",      icon: "heart.fill", title: "Devoted",
                description: "30-day streak",                       category: .loyal, isSecret: false),
    Achievement(id: "streak_100",     icon: "diamond.fill", title: "Inseparable",
                description: "100-day streak",                      category: .loyal, isSecret: true),
    Achievement(id: "two_weeks",      icon: "calendar", title: "Two Weeks In",
                description: "14 days since adoption",              category: .loyal, isSecret: false),
    Achievement(id: "birthday",       icon: "gift.fill", title: "Happy Birthday!",
                description: "1 year since adoption",               category: .loyal, isSecret: true),

    // ── Play ──────────────────────────────────────────────────────────────────
    Achievement(id: "laser",          icon: "scope", title: "Laser Enthusiast",
                description: "Used the laser pointer",              category: .play, isSecret: false),
    Achievement(id: "circus_act",     icon: "circle.dotted", title: "Circus Act",
                description: "Laser + Hyper speed simultaneously",  category: .play,     isSecret: true),
    Achievement(id: "all_skins",      icon: "paintpalette.fill", title: "Fashionista",
                description: "Tried all 6 bundled companions",            category: .play, isSecret: false),
    Achievement(id: "level_5",        icon: "star.fill", title: "Leveling Up",
                description: "Reached level 5",                     category: .play, isSecret: false),
    Achievement(id: "level_10",       icon: "star.circle.fill", title: "Veteran",
                description: "Reached level 10",                    category: .play, isSecret: false),

    // ── Secret ────────────────────────────────────────────────────────────────
    Achievement(id: "early_bird",     icon: "sunrise.fill", title: "Early Bird",
                description: "Used the app before 7 AM",           category: .secret, isSecret: true),
    Achievement(id: "night_owl",      icon: "moon.stars.fill", title: "Night Owl",
                description: "Used the app between 2–4 AM",        category: .secret, isSecret: true),
    Achievement(id: "level_20",       icon: "crown.fill", title: "Legend",
                description: "Reached level 20",                    category: .secret, isSecret: true),
    Achievement(id: "laser_100",      icon: "scope", title: "Red Obsession",
                description: "Used the laser pointer 100 times",   category: .secret, isSecret: true),
    Achievement(id: "easter_egg",     icon: "sparkles", title: "I Found It",
                description: "Discovered the hidden easter egg",    category: .secret, isSecret: true),
]

// MARK: – Achievement translations

extension Strings {
    static let achievementTable: [String: [Language: String]] = [
        "achievement.category.explorer": [.english: "Explorer", .simplifiedChinese: "探索", .traditionalChinese: "探索"],
        "achievement.category.sleeper": [.english: "Sleeper", .simplifiedChinese: "睡眠", .traditionalChinese: "睡眠"],
        "achievement.category.chaos": [.english: "Chaos", .simplifiedChinese: "捣蛋", .traditionalChinese: "搗蛋"],
        "achievement.category.loyal": [.english: "Loyal", .simplifiedChinese: "陪伴", .traditionalChinese: "陪伴"],
        "achievement.category.play": [.english: "Play", .simplifiedChinese: "玩耍", .traditionalChinese: "玩耍"],
        "achievement.category.secret": [.english: "Secret", .simplifiedChinese: "隐藏", .traditionalChinese: "隱藏"],
        "achievements.windowTitle": [.english: "Achievements", .simplifiedChinese: "成就", .traditionalChinese: "成就"],
        "achievements.title": [.english: "ACHIEVEMENTS", .simplifiedChinese: "成就", .traditionalChinese: "成就"],
        "achievements.progress": [.english: "%d of %d unlocked", .simplifiedChinese: "已解锁 %d / %d", .traditionalChinese: "已解鎖 %d / %d"],
        "achievements.all": [.english: "All", .simplifiedChinese: "全部", .traditionalChinese: "全部"],
        "achievements.secret": [.english: "Secret achievement", .simplifiedChinese: "隐藏成就", .traditionalChinese: "隱藏成就"],
        "achievements.unlocked": [.english: "Achievement Unlocked!", .simplifiedChinese: "解锁新成就！", .traditionalChinese: "解鎖新成就！"],
        "achievements.viewAll": [.english: "View All Achievements", .simplifiedChinese: "查看全部成就", .traditionalChinese: "查看全部成就"],

        "achievement.first_step.title": [.english: "First Step", .simplifiedChinese: "迈出第一步", .traditionalChinese: "踏出第一步"],
        "achievement.first_step.description": [.english: "Your cat started walking", .simplifiedChinese: "猫咪开始走路了", .traditionalChinese: "貓咪開始走路了"],
        "achievement.hundred_meters.title": [.english: "Night Walker", .simplifiedChinese: "夜行者", .traditionalChinese: "夜行者"],
        "achievement.hundred_meters.description": [.english: "Walked 100 meters", .simplifiedChinese: "累计走了 100 米", .traditionalChinese: "累計走了 100 公尺"],
        "achievement.one_km.title": [.english: "Kilometer Club", .simplifiedChinese: "一公里俱乐部", .traditionalChinese: "一公里俱樂部"],
        "achievement.one_km.description": [.english: "Walked 1 kilometer", .simplifiedChinese: "累计走了 1 公里", .traditionalChinese: "累計走了 1 公里"],
        "achievement.ten_km.title": [.english: "Marathon Cat", .simplifiedChinese: "马拉松猫咪", .traditionalChinese: "馬拉松貓咪"],
        "achievement.ten_km.description": [.english: "Walked 10 kilometers", .simplifiedChinese: "累计走了 10 公里", .traditionalChinese: "累計走了 10 公里"],
        "achievement.hundred_km.title": [.english: "World Tour", .simplifiedChinese: "环游世界", .traditionalChinese: "環遊世界"],
        "achievement.hundred_km.description": [.english: "Walked 100 kilometers", .simplifiedChinese: "累计走了 100 公里", .traditionalChinese: "累計走了 100 公里"],
        "achievement.speed_demon.title": [.english: "Speed Demon", .simplifiedChinese: "速度狂魔", .traditionalChinese: "速度狂魔"],
        "achievement.speed_demon.description": [.english: "Activated Hyper speed", .simplifiedChinese: "开启极速模式", .traditionalChinese: "開啟極速模式"],
        "achievement.slow_life.title": [.english: "Slow Life", .simplifiedChinese: "慢生活", .traditionalChinese: "慢生活"],
        "achievement.slow_life.description": [.english: "Activated Lazy mode", .simplifiedChinese: "开启慵懒模式", .traditionalChinese: "開啟慵懶模式"],

        "achievement.nap_10.title": [.english: "Nap Champion", .simplifiedChinese: "小睡冠军", .traditionalChinese: "小睡冠軍"],
        "achievement.nap_10.description": [.english: "10 naps taken", .simplifiedChinese: "累计小睡 10 次", .traditionalChinese: "累計小睡 10 次"],
        "achievement.nap_100.title": [.english: "Sleepyhead", .simplifiedChinese: "小瞌睡虫", .traditionalChinese: "小瞌睡蟲"],
        "achievement.nap_100.description": [.english: "100 naps taken", .simplifiedChinese: "累计小睡 100 次", .traditionalChinese: "累計小睡 100 次"],
        "achievement.nap_1000.title": [.english: "Comatose", .simplifiedChinese: "沉睡大师", .traditionalChinese: "沉睡大師"],
        "achievement.nap_1000.description": [.english: "1000 naps taken", .simplifiedChinese: "累计小睡 1000 次", .traditionalChinese: "累計小睡 1000 次"],
        "achievement.docked_first.title": [.english: "Up in the Attic", .simplifiedChinese: "阁楼小憩", .traditionalChinese: "閣樓小憩"],
        "achievement.docked_first.description": [.english: "Docked to the menu bar", .simplifiedChinese: "在菜单栏歇脚", .traditionalChinese: "在選單列歇腳"],
        "achievement.docked_long.title": [.english: "Cryogenic", .simplifiedChinese: "深度冬眠", .traditionalChinese: "深度冬眠"],
        "achievement.docked_long.description": [.english: "Stayed docked for 1 hour straight", .simplifiedChinese: "在菜单栏连续休息 1 小时", .traditionalChinese: "在選單列連續休息 1 小時"],

        "achievement.scratch_10.title": [.english: "Scratcher", .simplifiedChinese: "磨爪新手", .traditionalChinese: "磨爪新手"],
        "achievement.scratch_10.description": [.english: "10 scratches", .simplifiedChinese: "累计抓挠 10 次", .traditionalChinese: "累計抓癢 10 次"],
        "achievement.scratch_100.title": [.english: "Wall Destroyer", .simplifiedChinese: "墙壁破坏王", .traditionalChinese: "牆壁破壞王"],
        "achievement.scratch_100.description": [.english: "100 scratches", .simplifiedChinese: "累计抓挠 100 次", .traditionalChinese: "累計抓癢 100 次"],
        "achievement.scratch_1000.title": [.english: "Demolition Expert", .simplifiedChinese: "拆家专家", .traditionalChinese: "拆家專家"],
        "achievement.scratch_1000.description": [.english: "1000 scratches", .simplifiedChinese: "累计抓挠 1000 次", .traditionalChinese: "累計抓癢 1000 次"],
        "achievement.giant_cat.title": [.english: "Kaiju Cat", .simplifiedChinese: "巨兽猫咪", .traditionalChinese: "巨獸貓咪"],
        "achievement.giant_cat.description": [.english: "Set cat size to 3×", .simplifiedChinese: "将猫咪大小设为 3 倍", .traditionalChinese: "將貓咪大小設為 3 倍"],
        "achievement.tiny_cat.title": [.english: "Quantum Cat", .simplifiedChinese: "量子猫咪", .traditionalChinese: "量子貓咪"],
        "achievement.tiny_cat.description": [.english: "Set cat size to 0.5×", .simplifiedChinese: "将猫咪大小设为 0.5 倍", .traditionalChinese: "將貓咪大小設為 0.5 倍"],

        "achievement.streak_7.title": [.english: "Loyal", .simplifiedChinese: "忠实伙伴", .traditionalChinese: "忠實夥伴"],
        "achievement.streak_7.description": [.english: "7-day streak", .simplifiedChinese: "连续 7 天启动应用", .traditionalChinese: "連續 7 天啟動應用程式"],
        "achievement.streak_30.title": [.english: "Devoted", .simplifiedChinese: "一心相伴", .traditionalChinese: "一心相伴"],
        "achievement.streak_30.description": [.english: "30-day streak", .simplifiedChinese: "连续 30 天启动应用", .traditionalChinese: "連續 30 天啟動應用程式"],
        "achievement.streak_100.title": [.english: "Inseparable", .simplifiedChinese: "形影不离", .traditionalChinese: "形影不離"],
        "achievement.streak_100.description": [.english: "100-day streak", .simplifiedChinese: "连续 100 天启动应用", .traditionalChinese: "連續 100 天啟動應用程式"],
        "achievement.two_weeks.title": [.english: "Two Weeks In", .simplifiedChinese: "两周纪念", .traditionalChinese: "兩週紀念"],
        "achievement.two_weeks.description": [.english: "14 days since adoption", .simplifiedChinese: "相伴已满 14 天", .traditionalChinese: "相伴已滿 14 天"],
        "achievement.birthday.title": [.english: "Happy Birthday!", .simplifiedChinese: "生日快乐！", .traditionalChinese: "生日快樂！"],
        "achievement.birthday.description": [.english: "1 year since adoption", .simplifiedChinese: "相伴已满 365 天", .traditionalChinese: "相伴已滿 365 天"],

        "achievement.laser.title": [.english: "Laser Enthusiast", .simplifiedChinese: "激光爱好者", .traditionalChinese: "雷射愛好者"],
        "achievement.laser.description": [.english: "Used the laser pointer", .simplifiedChinese: "使用过激光逗猫", .traditionalChinese: "使用過雷射逗貓"],
        "achievement.circus_act.title": [.english: "Circus Act", .simplifiedChinese: "马戏表演", .traditionalChinese: "馬戲表演"],
        "achievement.circus_act.description": [.english: "Laser + Hyper speed simultaneously", .simplifiedChinese: "同时开启激光逗猫和极速模式", .traditionalChinese: "同時開啟雷射逗貓和極速模式"],
        "achievement.all_skins.title": [.english: "Fashionista", .simplifiedChinese: "时尚达人", .traditionalChinese: "時尚達人"],
        "achievement.all_skins.description": [
            .simplifiedChinese: "试过全部 6 位内置伙伴", .traditionalChinese: "試過全部 6 位內建夥伴",
            .english: "Tried all 6 bundled companions", .french: "Essayer les 6 compagnons intégrés",
            .japanese: "内蔵の仲間 6 種をすべて使う", .german: "Alle 6 enthaltenen Begleiter ausprobiert",
            .spanish: "Probaste los 6 compañeros incluidos",
        ],
        "achievement.level_5.title": [.english: "Leveling Up", .simplifiedChinese: "不断成长", .traditionalChinese: "不斷成長"],
        "achievement.level_5.description": [.english: "Reached level 5", .simplifiedChinese: "达到 5 级", .traditionalChinese: "達到 5 級"],
        "achievement.level_10.title": [.english: "Veteran", .simplifiedChinese: "资深伙伴", .traditionalChinese: "資深夥伴"],
        "achievement.level_10.description": [.english: "Reached level 10", .simplifiedChinese: "达到 10 级", .traditionalChinese: "達到 10 級"],

        "achievement.early_bird.title": [.english: "Early Bird", .simplifiedChinese: "早起的猫儿", .traditionalChinese: "早起的貓兒"],
        "achievement.early_bird.description": [.english: "Used the app before 7 AM", .simplifiedChinese: "早上 7 点前使用应用", .traditionalChinese: "早上 7 點前使用應用程式"],
        "achievement.night_owl.title": [.english: "Night Owl", .simplifiedChinese: "夜猫子", .traditionalChinese: "夜貓子"],
        "achievement.night_owl.description": [.english: "Used the app between 2–4 AM", .simplifiedChinese: "凌晨 2 至 4 点使用应用", .traditionalChinese: "凌晨 2 至 4 點使用應用程式"],
        "achievement.level_20.title": [.english: "Legend", .simplifiedChinese: "传奇伙伴", .traditionalChinese: "傳奇夥伴"],
        "achievement.level_20.description": [.english: "Reached level 20", .simplifiedChinese: "达到 20 级", .traditionalChinese: "達到 20 級"],
        "achievement.laser_100.title": [.english: "Red Obsession", .simplifiedChinese: "追光狂热者", .traditionalChinese: "追光狂熱者"],
        "achievement.laser_100.description": [.english: "Used the laser pointer 100 times", .simplifiedChinese: "累计使用激光逗猫 100 次", .traditionalChinese: "累計使用雷射逗貓 100 次"],
        "achievement.easter_egg.title": [.english: "I Found It", .simplifiedChinese: "找到啦", .traditionalChinese: "找到啦"],
        "achievement.easter_egg.description": [.english: "Discovered the hidden easter egg", .simplifiedChinese: "发现了隐藏彩蛋", .traditionalChinese: "發現了隱藏彩蛋"],
    ]
}
