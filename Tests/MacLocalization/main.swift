import Foundation

let localeCases: [([String], Language)] = [
    ([], .english),
    (["zh"], .simplifiedChinese),
    (["zh-Hans"], .simplifiedChinese),
    (["zh-Hans-CN"], .simplifiedChinese),
    (["zh-CN"], .simplifiedChinese),
    (["zh-SG"], .simplifiedChinese),
    (["ZH_hAnS_sG"], .simplifiedChinese),
    (["zh-Hans-HK"], .simplifiedChinese),
    (["zh-Hant"], .traditionalChinese),
    (["zh-Hant-CN"], .traditionalChinese),
    (["zh-Hant-TW"], .traditionalChinese),
    (["zh-Hant-HK"], .traditionalChinese),
    (["zh-Hant-MO"], .traditionalChinese),
    (["zh-Hant-SG"], .traditionalChinese),
    (["zh-TW"], .traditionalChinese),
    (["zh-HK"], .traditionalChinese),
    (["zh-MO"], .traditionalChinese),
    (["ZH_hAnT_tw"], .traditionalChinese),
    (["zh-Hans-TW"], .simplifiedChinese),
    (["zh-Hans-MO"], .simplifiedChinese),
    (["zh-TW", "ja-JP"], .traditionalChinese),
    (["zh-Hant", "zh-Hans"], .traditionalChinese),
    (["zh-Hans", "zh-Hant"], .simplifiedChinese),
    (["ko-KR", "zh-Hant"], .traditionalChinese),
    (["ko-KR", "zh-CN", "en"], .simplifiedChinese),
    (["fr-CA", "zh-CN"], .french),
    (["en-US", "zh-Hans"], .english),
    (["de-DE"], .german),
    (["es-MX"], .spanish),
    (["ko-KR"], .english),
]
for (identifiers, expected) in localeCases {
    precondition(Language.resolve(preferredLanguages: identifiers) == expected, "Incorrect resolution: \(identifiers)")
}

precondition(Language.allCases.count == 7)
precondition(Language(rawValue: "zh-Hans") == .simplifiedChinese)
precondition(Language(rawValue: "zh-Hant") == .traditionalChinese)
let keys = Set(Strings.table.keys)
precondition(keys.isDisjoint(with: Strings.achievementTable.keys))
let translations = Strings.table.merging(Strings.achievementTable) { _, _ in fatalError("Duplicate key") }
precondition(AchievementRules.bundledSkinIDs.count == 6)
precondition(AchievementRules.bundledSkinIDs.contains("piaopiao"))
precondition(AchievementRules.allBundledSkinsUsed(AchievementRules.bundledSkinIDs))
precondition(!AchievementRules.allBundledSkinsUsed(["piaopiao"]))
for missing in AchievementRules.bundledSkinIDs {
    precondition(!AchievementRules.allBundledSkinsUsed(AchievementRules.bundledSkinIDs.subtracting([missing])))
}
precondition(Strings.table["ob.welcome.title"]?[.english] == "Welcome to PiaoPal")
precondition(Strings.table["settings.quit"]?[.english] == "Quit PiaoPal")
for (key, values) in Strings.table {
    if key.hasPrefix("brand.") || key.hasPrefix("skin.") || key.hasPrefix("nav.") {
        precondition(Set(values.keys) == Set(Language.allCases), "Incomplete localization: \(key)")
    }
    if key != "brand.original_credit" {
        precondition(values.values.allSatisfy { !$0.contains("OnekoMac") }, "Obsolete visible brand: \(key)")
    }
}
let placeholder = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+)?(?:\.\d+)?[a-zA-Z@]"#)
func specifiers(_ value: String) -> [String] {
    placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
        String(value[Range($0.range, in: value)!])
    }
}
for (key, values) in translations {
    guard let english = values[.english], let chinese = values[.simplifiedChinese],
          let traditional = values[.traditionalChinese] else {
        fatalError("Missing English/Simplified/Traditional Chinese: \(key)")
    }
    precondition(!chinese.isEmpty, "Empty Chinese: \(key)")
    precondition(!traditional.isEmpty, "Empty Traditional Chinese: \(key)")
    for (language, text) in values {
        precondition(specifiers(text) == specifiers(english), "Placeholder mismatch: \(key) \(language)")
    }
}

// The volatile argument domain is process-local; no user preferences are written.
UserDefaults.standard.setVolatileDomain(["app_language": "zh-Hans"], forName: UserDefaults.argumentDomain)
let chinese = LanguageManager()
precondition(chinese.language == .simplifiedChinese)
precondition(chinese["settings.skin"] == "皮肤")
precondition(chinese.appName == "飘伴")
precondition(chinese.skinName(for: "piaopiao") == "飘飘")
precondition(chinese["ob.welcome.title"] == "欢迎使用飘伴")
precondition(chinese["settings.quit"] == "退出飘伴")
precondition(chinese["unknown.key"] == "unknown.key")
precondition(chinese.format("stats.level", 5) == "5 级")
precondition(chinese.format("stats.walked_distance", 42) == "已走 42 米")
precondition(chinese.format("stats.next_level", 12.0, 5) == "再走 12 米升至 5 级")
precondition(chinese.format("stats.xp_progress", 12, 40) == "12 米 / 40 米")
precondition(chinese.format("achievements.progress", 2, 32) == "已解锁 2 / 32")
precondition(chinese.format("distance.kilometers", 1.5) == "1.5 公里")
for achievement in allAchievements {
    precondition(achievement.localizedTitle(using: chinese) != achievement.title)
    precondition(achievement.localizedDescription(using: chinese) != achievement.description)
}
UserDefaults.standard.setVolatileDomain(["app_language": "zh-Hant"], forName: UserDefaults.argumentDomain)
let traditional = LanguageManager()
precondition(traditional.language == .traditionalChinese)
precondition(traditional["settings.skin"] == "造型")
precondition(traditional.appName == "飄伴")
precondition(traditional.skinName(for: "piaopiao") == "飄飄")
precondition(traditional["ob.welcome.title"] == "歡迎使用飄伴")
precondition(traditional["settings.quit"] == "結束飄伴")
precondition(traditional["menu.settings"] == "設定")
precondition(traditional["menu.laser"] == "雷射逗貓")
precondition(traditional.format("stats.level", 5) == "5 級")
precondition(traditional.format("stats.walked_distance", 42) == "已走 42 公尺")
precondition(traditional.format("stats.next_level", 12.0, 5) == "再走 12 公尺升至 5 級")
precondition(traditional.format("stats.xp_progress", 12, 40) == "12 公尺 / 40 公尺")
precondition(traditional.format("achievements.progress", 2, 32) == "已解鎖 2 / 32")
precondition(traditional.format("distance.kilometers", 1.5) == "1.5 公里")
for achievement in allAchievements {
    precondition(achievement.localizedTitle(using: traditional) != achievement.title)
    precondition(achievement.localizedDescription(using: traditional) != achievement.description)
}
for language in Language.allCases {
    UserDefaults.standard.setVolatileDomain(["app_language": language.rawValue], forName: UserDefaults.argumentDomain)
    let manager = LanguageManager()
    precondition(manager.language == language)
    precondition(manager.personality(for: "classic") == manager["personality.classic"])
    precondition(manager.personality(for: "downloaded-cat") == manager["personality.custom"])
    precondition(manager.personality(for: "") == manager["personality.custom"])
    precondition(manager.personality(for: "piaopiao") == manager["personality.piaopiao"])
    precondition(manager.petDisplayName("", skinID: "piaopiao") == manager.skinName(for: "piaopiao"))
    precondition(manager.petDisplayName(" \n", skinID: "piaopiao") == manager.skinName(for: "piaopiao"))
    // App renaming and skin switching do not overwrite an existing pet nickname.
    for nickname in ["Neko", "Classic", "我的猫", "My PiaoPiao"] {
        precondition(manager.petDisplayName(nickname, skinID: "piaopiao") == nickname)
    }
    precondition(manager.skinName(for: "classic") == manager["skin.classic"])
    for id in AchievementRules.bundledSkinIDs {
        precondition(manager.skinName(for: id) != id.capitalized)
    }
    precondition(manager.skinName(for: "downloaded-cat") == "Downloaded-Cat")
    precondition(manager.appName != manager.skinName(for: "piaopiao"))
    if language == .english {
        precondition(manager.appName == "PiaoPal")
        precondition(manager.skinName(for: "piaopiao") == "PiaoPiao")
    }
    for key in translations.keys {
        precondition(manager[key] != key, "Raw key in UI: \(language) \(key)")
    }
    if language != .simplifiedChinese && language != .traditionalChinese {
        for achievement in allAchievements {
            precondition(achievement.localizedTitle(using: manager) == achievement.title)
            let translatedDescription = Strings.achievementTable["achievement.\(achievement.id).description"]?[language]
            precondition(achievement.localizedDescription(using: manager) == (translatedDescription ?? achievement.description))
        }
    }
}
print("PASS: \(localeCases.count) locale cases; \(translations.count) English/Simplified/Traditional entries; matching format placeholders; all 7 languages; all \(allAchievements.count) achievements; independent PiaoPal catalog; six companion names; nickname preservation")
