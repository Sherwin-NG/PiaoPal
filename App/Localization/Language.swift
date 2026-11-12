import Foundation

// MARK: – Language enum

enum Language: String, CaseIterable, Identifiable {
    case english  = "en"
    case french   = "fr"
    case japanese = "ja"
    case german   = "de"
    case spanish  = "es"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .english:  "🇬🇧"
        case .french:   "🇫🇷"
        case .japanese: "🇯🇵"
        case .german:   "🇩🇪"
        case .spanish:  "🇪🇸"
        case .simplifiedChinese: "🇨🇳"
        case .traditionalChinese: "🇨🇳"
        }
    }

    var displayName: String {
        switch self {
        case .english:  "English"
        case .french:   "Français"
        case .japanese: "日本語"
        case .german:   "Deutsch"
        case .spanish:  "Español"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    /// Picks the first supported language, respecting explicit Chinese script and region.
    static func resolve(preferredLanguages: [String]) -> Language {
        for identifier in preferredLanguages {
            let components = identifier.replacingOccurrences(of: "_", with: "-")
                .lowercased().split(separator: "-").map(String.init)
            guard let languageCode = components.first else { continue }
            switch languageCode {
            case "en": return .english
            case "fr": return .french
            case "ja": return .japanese
            case "de": return .german
            case "es": return .spanish
            case "zh":
                // An explicit script takes precedence over the region.
                if components.contains("hant") { return .traditionalChinese }
                if components.contains("hans") { return .simplifiedChinese }
                if components.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return .traditionalChinese }
                if components.count == 1 || components.contains("cn") || components.contains("sg") {
                    return .simplifiedChinese
                }
            default: continue
            }
        }
        return .english
    }
}

// MARK: – LanguageManager

import Combine

final class LanguageManager: ObservableObject {
    @Published private(set) var language: Language

    init() {
        if let stored = UserDefaults.standard.string(forKey: "app_language"),
           let lang = Language(rawValue: stored) {
            language = lang
        } else {
            language = Language.resolve(preferredLanguages: Locale.preferredLanguages)
        }
    }

    func set(_ lang: Language) {
        language = lang
        UserDefaults.standard.set(lang.rawValue, forKey: "app_language")
    }

    subscript(_ key: String) -> String {
        let translations = Strings.table[key] ?? Strings.achievementTable[key]
        return translations?[language] ?? translations?[.english] ?? key
    }

    var appName: String { self["brand.name"] }

    func skinName(for skinID: String) -> String {
        let key = "skin.\(skinID)"
        return Strings.table[key] == nil ? skinID.capitalized : self[key]
    }

    /// A display fallback only: existing nicknames and preference keys stay intact.
    func petDisplayName(_ savedName: String, skinID: String) -> String {
        let name = savedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? skinName(for: skinID) : name
    }

    /// Uses a localized fallback for downloaded skins without a predefined personality.
    func personality(for skinID: String) -> String {
        let key = "personality.\(skinID)"
        return self[Strings.table[key] == nil ? "personality.custom" : key]
    }

    /// Formats a complete translated sentence, allowing each language to order its arguments.
    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: self[key], locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

// MARK: – Strings table

enum Strings {
    static let table: [String: [Language: String]] = [
        "brand.credits": [
            .simplifiedChinese: "开源许可与致谢", .traditionalChinese: "開源授權與致謝", .english: "Open-source licenses & credits",
            .french: "Licences libres et crédits", .japanese: "オープンソースのライセンスと謝辞", .german: "Open-Source-Lizenzen & Danksagungen", .spanish: "Licencias y créditos de código abierto",
        ],
        "skin.classic": [
            .simplifiedChinese: "团团",
            .traditionalChinese: "團團",
            .english: "TuanTuan",
            .french: "TuanTuan",
            .japanese: "TuanTuan",
            .german: "TuanTuan",
            .spanish: "TuanTuan",
        ],
        "skin.dog": [
            .simplifiedChinese: "豆豆",
            .traditionalChinese: "豆豆",
            .english: "Dodo",
            .french: "Dodo",
            .japanese: "Dodo",
            .german: "Dodo",
            .spanish: "Dodo",
        ],
        "skin.tora": [
            .simplifiedChinese: "斑斑",
            .traditionalChinese: "斑斑",
            .english: "BanBan",
            .french: "BanBan",
            .japanese: "BanBan",
            .german: "BanBan",
            .spanish: "BanBan",
        ],
        "skin.maia": [
            .simplifiedChinese: "桃桃",
            .traditionalChinese: "桃桃",
            .english: "TaoTao",
            .french: "TaoTao",
            .japanese: "TaoTao",
            .german: "TaoTao",
            .spanish: "TaoTao",
        ],
        "skin.vaporwave": [
            .simplifiedChinese: "暮暮",
            .traditionalChinese: "暮暮",
            .english: "MuMu",
            .french: "MuMu",
            .japanese: "MuMu",
            .german: "MuMu",
            .spanish: "MuMu",
        ],
        "nav.language": [
            .simplifiedChinese: "语言",
            .traditionalChinese: "語言",
            .english: "Language",
            .french: "Langue",
            .japanese: "言語",
            .german: "Sprache",
            .spanish: "Idioma",
        ],
        "nav.meet": [
            .simplifiedChinese: "认识飘伴",
            .traditionalChinese: "認識飄伴",
            .english: "Meet PiaoPal",
            .french: "Voici PiaoPal",
            .japanese: "PiaoPal について",
            .german: "PiaoPal kennenlernen",
            .spanish: "Conoce PiaoPal",
        ],
        "nav.companion": [
            .simplifiedChinese: "选择伙伴",
            .traditionalChinese: "選擇夥伴",
            .english: "Companion",
            .french: "Compagnon",
            .japanese: "仲間を選ぶ",
            .german: "Begleiter",
            .spanish: "Compañero",
        ],
        "nav.name": [
            .simplifiedChinese: "起个昵称",
            .traditionalChinese: "取個暱稱",
            .english: "Nickname",
            .french: "Surnom",
            .japanese: "ニックネーム",
            .german: "Spitzname",
            .spanish: "Apodo",
        ],
        "nav.card": [
            .simplifiedChinese: "陪伴卡",
            .traditionalChinese: "陪伴卡",
            .english: "Companion card",
            .french: "Carte de compagnon",
            .japanese: "パートナーカード",
            .german: "Begleiterkarte",
            .spanish: "Tarjeta de compañía",
        ],
        "marketplace.local": [
            .simplifiedChinese: "正在展示内置伙伴；暂时无法检查新伙伴。",
            .traditionalChinese: "正在顯示內建夥伴；暫時無法檢查新夥伴。",
            .english: "Showing bundled companions. New companions could not be checked.",
            .french: "Compagnons intégrés affichés. Impossible de vérifier les nouveautés.",
            .japanese: "内蔵の仲間を表示しています。新しい仲間を確認できませんでした。",
            .german: "Enthaltene Begleiter werden angezeigt. Neue Begleiter konnten nicht geprüft werden.",
            .spanish: "Se muestran los compañeros incluidos. No se pudieron consultar novedades.",
        ],
        "marketplace.credit.original": [
            .simplifiedChinese: "开源素材",
            .traditionalChinese: "開源素材",
            .english: "Open-source artwork",
            .french: "Illustrations libres",
            .japanese: "オープンソース素材",
            .german: "Open-Source-Grafiken",
            .spanish: "Arte de código abierto",
        ],
        "marketplace.credit.piaopiao": [
            .simplifiedChinese: "Sherwin-NG · AI 辅助",
            .traditionalChinese: "Sherwin-NG · AI 輔助",
            .english: "Sherwin-NG · AI-assisted",
            .french: "Sherwin-NG · avec IA",
            .japanese: "Sherwin-NG · AI 使用",
            .german: "Sherwin-NG · KI-gestützt",
            .spanish: "Sherwin-NG · con IA",
        ],
        "brand.could_not_start": [
            .simplifiedChinese: "飘伴无法启动", .traditionalChinese: "飄伴無法啟動", .english: "PiaoPal could not start",
            .french: "PiaoPal n’a pas pu démarrer", .japanese: "PiaoPal を起動できませんでした",
            .german: "PiaoPal konnte nicht gestartet werden", .spanish: "No se pudo iniciar PiaoPal",
        ],
        "brand.license": [
            .simplifiedChinese: "查看 MIT 许可证", .traditionalChinese: "檢視 MIT 授權條款", .english: "View MIT license",
            .french: "Voir la licence MIT", .japanese: "MIT ライセンスを表示", .german: "MIT-Lizenz anzeigen",
            .spanish: "Ver licencia MIT",
        ],
        "brand.piaopiao_credit": [
            .simplifiedChinese: "飘飘的照片由 Sherwin 提供；形象经 AI 辅助制作。", .traditionalChinese: "飄飄的照片由 Sherwin 提供；形象經 AI 輔助製作。",
            .english: "PiaoPiao reference photos by Sherwin; artwork created with AI assistance.",
            .french: "Photos de PiaoPiao par Sherwin ; illustrations créées avec l’aide de l’IA.",
            .japanese: "PiaoPiao の参考写真：Sherwin。画像制作には AI を使用しています。",
            .german: "PiaoPiaos Referenzfotos von Sherwin; Gestaltung mit KI-Unterstützung.",
            .spanish: "Fotos de referencia de PiaoPiao por Sherwin; arte creado con ayuda de IA.",
        ],
        "brand.original_credit": [
            .simplifiedChinese: "基于 OnekoMac，由 hellov3an 创作。", .traditionalChinese: "基於 OnekoMac，由 hellov3an 創作。",
            .english: "Based on OnekoMac by hellov3an.", .french: "Basé sur OnekoMac, créé par hellov3an.",
            .japanese: "hellov3an 作の OnekoMac をベースにしています。", .german: "Basiert auf OnekoMac von hellov3an.",
            .spanish: "Basado en OnekoMac de hellov3an.",
        ],
        "personality.piaopiao": [
            .simplifiedChinese: "以真实猫咪飘飘为原型", .traditionalChinese: "以真實貓咪飄飄為原型",
            .english: "Inspired by the real PiaoPiao", .french: "Inspirée de la vraie PiaoPiao",
            .japanese: "実在の猫 PiaoPiao がモデル", .german: "Nach der echten Katze PiaoPiao",
            .spanish: "Inspirada en la gata real PiaoPiao",
        ],
        "skin.piaopiao": [
            .simplifiedChinese: "飘飘", .traditionalChinese: "飄飄", .english: "PiaoPiao",
            .french: "PiaoPiao", .japanese: "PiaoPiao", .german: "PiaoPiao", .spanish: "PiaoPiao",
        ],
        "brand.name": [
            .simplifiedChinese: "飘伴", .traditionalChinese: "飄伴", .english: "PiaoPal",
            .french: "PiaoPal", .japanese: "PiaoPal", .german: "PiaoPal", .spanish: "PiaoPal",
        ],

        // ── Onboarding – Concept ──────────────────────────────────────────────
        "ob.concept.eyebrow": [
            .simplifiedChinese: "飘伴 PiaoPal", .traditionalChinese: "飄伴 PiaoPal", .english: "PiaoPal",
            .french: "PiaoPal", .japanese: "PiaoPal", .german: "PiaoPal", .spanish: "PiaoPal",
        ],
        "ob.concept.title": [
            .simplifiedChinese: "这是飘飘。", .traditionalChinese: "這是飄飄。", .english: "Meet PiaoPiao.",
            .french: "Voici PiaoPiao.", .japanese: "PiaoPiao です。", .german: "Das ist PiaoPiao.",
            .spanish: "Te presentamos a PiaoPiao.",
        ],
        "ob.concept.f1": [
            .traditionalChinese: "跟著游標，走到哪裡都相隨",
            .simplifiedChinese: "跟着鼠标指针，走到哪里都相随",
            .english:  "Follows your cursor — everywhere",
            .french:   "Suit ton curseur — partout",
            .japanese: "カーソルをどこでも追いかける",
            .german:   "Folgt deinem Cursor — überall",
            .spanish:  "Sigue tu cursor — a todas partes",
        ],
        "ob.concept.f2": [
            .traditionalChinese: "發發呆、抓抓癢，累了就睡",
            .simplifiedChinese: "发发呆、挠挠痒，困了就睡",
            .english:  "Idles, scratches walls, falls asleep",
            .french:   "Se repose, gratte les murs, s'endort",
            .japanese: "休んで、壁を引っかいて、眠る",
            .german:   "Ruht, kratzt Wände, schläft ein",
            .spanish:  "Descansa, araña paredes, se duerme",
        ],
        "ob.concept.f3": [
            .traditionalChinese: "在你的所有螢幕之間自由穿梭",
            .simplifiedChinese: "在你的所有屏幕之间自由穿梭",
            .english:  "Crosses between all your screens",
            .french:   "Traverse tous tes écrans",
            .japanese: "すべての画面を行き来する",
            .german:   "Wechselt zwischen all deinen Bildschirmen",
            .spanish:  "Cruza entre todas tus pantallas",
        ],

        // ── Onboarding – Language ─────────────────────────────────────────────
        "ob.lang.title": [
            .traditionalChinese: "選擇語言",
            .simplifiedChinese: "选择语言",
            .english:  "Choose your language",
            .french:   "Choisissez votre langue",
            .japanese: "言語を選んでください",
            .german:   "Wähle deine Sprache",
            .spanish:  "Elige tu idioma",
        ],

        // ── Onboarding – Cat ──────────────────────────────────────────────────
        "ob.cat.title": [
            .traditionalChinese: "選擇你的小夥伴",
            .simplifiedChinese: "选择你的小伙伴",
            .english:  "Pick your companion",
            .french:   "Choisissez votre compagnon",
            .japanese: "相棒を選んでください",
            .german:   "Wähle deinen Begleiter",
            .spanish:  "Elige tu compañero",
        ],
        "ob.cat.subtitle": [
            .traditionalChinese: "隨時可以在設定中更換。",
            .simplifiedChinese: "随时可以在设置中更换。",
            .english:  "You can switch anytime in settings.",
            .french:   "Modifiable à tout moment dans les réglages.",
            .japanese: "設定でいつでも変更できます。",
            .german:   "In den Einstellungen jederzeit änderbar.",
            .spanish:  "Puedes cambiarlo en cualquier momento.",
        ],

        // ── Onboarding – ID Card ─────────────────────────────────────────────
        "ob.card.eyebrow": [
            .simplifiedChinese: "陪伴卡", .traditionalChinese: "陪伴卡", .english: "COMPANION CARD",
            .french: "CARTE DE COMPAGNON", .japanese: "パートナーカード", .german: "BEGLEITERKARTE",
            .spanish: "TARJETA DE COMPAÑÍA",
        ],
        "ob.card.adopted": [
            .simplifiedChinese: "相伴起点", .traditionalChinese: "相伴起點", .english: "Together since",
            .french: "Ensemble depuis", .japanese: "一緒になった日", .german: "Zusammen seit", .spanish: "Juntos desde",
        ],
        "ob.card.personality": [
            .simplifiedChinese: "角色介绍", .traditionalChinese: "角色介紹", .english: "Character",
            .french: "Personnage", .japanese: "キャラクター", .german: "Figur", .spanish: "Personaje",
        ],
        "personality.classic": [
            .traditionalChinese: "經典又忠誠",
            .simplifiedChinese: "经典又忠诚",
            .english:  "Classic & Loyal",
            .french:   "Classique & fidèle",
            .japanese: "古典的で忠実",
            .german:   "Klassisch & treu",
            .spanish:  "Clásico & fiel",
        ],
        "personality.dog": [
            .traditionalChinese: "活潑好動",
            .simplifiedChinese: "活泼好动",
            .english:  "Playful & Energetic",
            .french:   "Joueur & énergique",
            .japanese: "遊び好きで元気",
            .german:   "Verspielt & energetisch",
            .spanish:  "Juguetón & enérgico",
        ],
        "personality.tora": [
            .traditionalChinese: "野性勇敢",
            .simplifiedChinese: "野性勇敢",
            .english:  "Wild & Brave",
            .french:   "Sauvage & courageux",
            .japanese: "野生的で勇敢",
            .german:   "Wild & mutig",
            .spanish:  "Salvaje & valiente",
        ],
        "personality.maia": [
            .traditionalChinese: "溫柔愛幻想",
            .simplifiedChinese: "温柔爱幻想",
            .english:  "Gentle & Dreamy",
            .french:   "Doux & rêveur",
            .japanese: "穏やかで夢見がち",
            .german:   "Sanft & verträumt",
            .spanish:  "Dulce & soñador",
        ],
        "personality.vaporwave": [
            .traditionalChinese: "復古神祕",
            .simplifiedChinese: "复古神秘",
            .english:  "Retro & Mysterious",
            .french:   "Rétro & mystérieux",
            .japanese: "レトロで神秘的",
            .german:   "Retro & mysteriös",
            .spanish:  "Retro & misterioso",
        ],

        // ── Onboarding – Welcome ──────────────────────────────────────────────
        "ob.welcome.title": [
            .simplifiedChinese: "欢迎使用飘伴", .traditionalChinese: "歡迎使用飄伴", .english: "Welcome to PiaoPal",
            .french: "Bienvenue sur PiaoPal", .japanese: "PiaoPalへようこそ", .german: "Willkommen bei PiaoPal",
            .spanish: "Bienvenido a PiaoPal",
        ],
        "ob.welcome.subtitle": [
            .traditionalChinese: "你的小貓已經準備好了。",
            .simplifiedChinese: "你的小猫已经准备好了。",
            .english:  "Your cat is ready.",
            .french:   "Ton chat est prêt.",
            .japanese: "猫の準備ができました。",
            .german:   "Deine Katze ist bereit.",
            .spanish:  "Tu gato está listo.",
        ],

        // ── Onboarding – Name ─────────────────────────────────────────────────
        "ob.name.title": [
            .traditionalChinese: "幫你的小貓取個名字吧",
            .simplifiedChinese: "给你的小猫起个名字吧",
            .english:  "What's your cat's name?",
            .french:   "Comment s'appelle-t-il ?",
            .japanese: "猫の名前は何ですか？",
            .german:   "Wie heißt deine Katze?",
            .spanish:  "¿Cómo se llama tu gato?",
        ],
        "ob.name.subtitle": [
            .traditionalChinese: "隨時可以在設定中修改。",
            .simplifiedChinese: "随时可以在设置中修改。",
            .english:  "You can change it anytime in settings.",
            .french:   "Modifiable à tout moment dans les réglages.",
            .japanese: "設定でいつでも変更できます。",
            .german:   "In den Einstellungen jederzeit änderbar.",
            .spanish:  "Puedes cambiarlo en cualquier momento.",
        ],

        // ── Navigation buttons ────────────────────────────────────────────────
        "btn.next": [
            .traditionalChinese: "下一步",
            .simplifiedChinese: "下一步",
            .english:  "Next",
            .french:   "Suivant",
            .japanese: "次へ",
            .german:   "Weiter",
            .spanish:  "Siguiente",
        ],
        "btn.back": [
            .traditionalChinese: "上一步",
            .simplifiedChinese: "上一步",
            .english:  "Back",
            .french:   "Retour",
            .japanese: "戻る",
            .german:   "Zurück",
            .spanish:  "Atrás",
        ],
        "btn.start": [
            .traditionalChinese: "出發吧！",
            .simplifiedChinese: "出发吧！",
            .english:  "Let's go!",
            .french:   "C'est parti !",
            .japanese: "さあ、行こう！",
            .german:   "Los geht's!",
            .spanish:  "¡Vamos!",
        ],

        // ── Settings ──────────────────────────────────────────────────────────
        "settings.skin": [
            .traditionalChinese: "造型",
            .simplifiedChinese: "皮肤",
            .english:  "Skin",
            .french:   "Skin",
            .japanese: "スキン",
            .german:   "Skin",
            .spanish:  "Skin",
        ],
        "settings.stats": [
            .traditionalChinese: "統計",
            .simplifiedChinese: "统计",
            .english:  "Statistics",
            .french:   "Statistiques",
            .japanese: "統計",
            .german:   "Statistiken",
            .spanish:  "Estadísticas",
        ],
        "settings.updates": [
            .traditionalChinese: "更新",
            .simplifiedChinese: "更新",
            .english:  "Updates",
            .french:   "Mises à jour",
            .japanese: "アップデート",
            .german:   "Updates",
            .spanish:  "Actualizaciones",
        ],
        "settings.debug": [
            .traditionalChinese: "除錯",
            .simplifiedChinese: "调试",
            .english:  "Debug",
            .french:   "Debug",
            .japanese: "デバッグ",
            .german:   "Debug",
            .spanish:  "Debug",
        ],
        "settings.reset": [
            .traditionalChinese: "重設",
            .simplifiedChinese: "重置",
            .english:  "Reset",
            .french:   "Réinitialiser",
            .japanese: "リセット",
            .german:   "Zurücksetzen",
            .spanish:  "Restablecer",
        ],
        "settings.quit": [
            .simplifiedChinese: "退出飘伴", .traditionalChinese: "結束飄伴", .english: "Quit PiaoPal",
            .french: "Quitter PiaoPal", .japanese: "PiaoPalを終了", .german: "PiaoPal beenden", .spanish: "Salir de PiaoPal",
        ],
        "settings.marketplace": [
            .traditionalChinese: "瀏覽造型",
            .simplifiedChinese: "浏览皮肤",
            .english:  "Browse Skins",
            .french:   "Parcourir les skins",
            .japanese: "スキンを探す",
            .german:   "Skins durchsuchen",
            .spanish:  "Explorar skins",
        ],

        // ── Marketplace ───────────────────────────────────────────────────────
        "marketplace.title": [
            .traditionalChinese: "造型市集",
            .simplifiedChinese: "皮肤市场",
            .english:  "Skin Marketplace",
            .french:   "Marketplace",
            .japanese: "スキン広場",
            .german:   "Skin-Marktplatz",
            .spanish:  "Mercado de Skins",
        ],
        "marketplace.subtitle": [
            .traditionalChinese: "探索並下載新造型",
            .simplifiedChinese: "发现并下载新皮肤",
            .english:  "Browse & download new skins",
            .french:   "Découvre et télécharge de nouveaux skins",
            .japanese: "新しいスキンを見つけよう",
            .german:   "Neue Skins entdecken & laden",
            .spanish:  "Descubre y descarga nuevos skins",
        ],
        "marketplace.loading": [
            .traditionalChinese: "正在載入…",
            .simplifiedChinese: "正在加载…",
            .english:  "Loading…",
            .french:   "Chargement…",
            .japanese: "読み込み中…",
            .german:   "Laden…",
            .spanish:  "Cargando…",
        ],
        "marketplace.bundled": [
            .traditionalChinese: "已內建",
            .simplifiedChinese: "已内置",
            .english:  "Included",
            .french:   "Inclus",
            .japanese: "収録済み",
            .german:   "Enthalten",
            .spanish:  "Incluido",
        ],
        "marketplace.download": [
            .traditionalChinese: "下載",
            .simplifiedChinese: "下载",
            .english:  "Download",
            .french:   "Télécharger",
            .japanese: "ダウンロード",
            .german:   "Herunterladen",
            .spanish:  "Descargar",
        ],
        "marketplace.installed": [
            .traditionalChinese: "已安裝",
            .simplifiedChinese: "已安装",
            .english:  "Installed",
            .french:   "Installé",
            .japanese: "インストール済み",
            .german:   "Installiert",
            .spanish:  "Instalado",
        ],
        "marketplace.error": [
            .traditionalChinese: "無法載入造型",
            .simplifiedChinese: "无法加载皮肤",
            .english:  "Couldn't load skins",
            .french:   "Impossible de charger les skins",
            .japanese: "スキンを読み込めません",
            .german:   "Skins konnten nicht geladen werden",
            .spanish:  "No se pudieron cargar los skins",
        ],
        "marketplace.retry": [
            .traditionalChinese: "重試",
            .simplifiedChinese: "重试",
            .english:  "Retry",
            .french:   "Réessayer",
            .japanese: "再試行",
            .german:   "Erneut versuchen",
            .spanish:  "Reintentar",
        ],

        "settings.check_btn": [
            .traditionalChinese: "檢查",
            .simplifiedChinese: "检查",
            .english:  "Check",
            .french:   "Vérifier",
            .japanese: "確認",
            .german:   "Prüfen",
            .spanish:  "Verificar",
        ],
        "settings.download_btn": [
            .traditionalChinese: "下載",
            .simplifiedChinese: "下载",
            .english:  "Download",
            .french:   "Télécharger",
            .japanese: "ダウンロード",
            .german:   "Herunterladen",
            .spanish:  "Descargar",
        ],

        // ── Stats labels ──────────────────────────────────────────────────────
        "stats.walked": [
            .traditionalChinese: "行走距離",
            .simplifiedChinese: "行走距离",
            .english:  "walked",
            .french:   "parcourus",
            .japanese: "歩いた",
            .german:   "gelaufen",
            .spanish:  "recorridos",
        ],
        "stats.nap": [
            .traditionalChinese: "次小睡",
            .simplifiedChinese: "次小睡",
            .english:  "nap",
            .french:   "sieste",
            .japanese: "昼寝",
            .german:   "Nickerchen",
            .spanish:  "siesta",
        ],
        "stats.naps": [
            .traditionalChinese: "次小睡",
            .simplifiedChinese: "次小睡",
            .english:  "naps",
            .french:   "siestes",
            .japanese: "昼寝",
            .german:   "Nickerchen",
            .spanish:  "siestas",
        ],
        "stats.scratch": [
            .traditionalChinese: "次抓癢",
            .simplifiedChinese: "次抓挠",
            .english:  "scratch",
            .french:   "grattage",
            .japanese: "引っかき",
            .german:   "Kratzen",
            .spanish:  "rasguño",
        ],
        "stats.scratches": [
            .traditionalChinese: "次抓癢",
            .simplifiedChinese: "次抓挠",
            .english:  "scratches",
            .french:   "grattages",
            .japanese: "引っかき",
            .german:   "Kratzer",
            .spanish:  "rasguños",
        ],
        "stats.together": [
            .traditionalChinese: "相伴時光",
            .simplifiedChinese: "相伴时光",
            .english:  "together",
            .french:   "ensemble",
            .japanese: "一緒に",
            .german:   "zusammen",
            .spanish:  "juntos",
        ],

        // ── Update status ─────────────────────────────────────────────────────
        "update.never": [
            .traditionalChinese: "尚未檢查更新",
            .simplifiedChinese: "尚未检查更新",
            .english:  "Never checked",
            .french:   "Jamais vérifié",
            .japanese: "未確認",
            .german:   "Nie geprüft",
            .spanish:  "Nunca verificado",
        ],
        "update.checking": [
            .traditionalChinese: "正在檢查…",
            .simplifiedChinese: "正在检查…",
            .english:  "Checking…",
            .french:   "Vérification…",
            .japanese: "確認中…",
            .german:   "Wird geprüft…",
            .spanish:  "Verificando…",
        ],
        "update.up_to_date": [
            .traditionalChinese: "已是最新版本",
            .simplifiedChinese: "已是最新版本",
            .english:  "Up to date",
            .french:   "À jour",
            .japanese: "最新版",
            .german:   "Aktuell",
            .spanish:  "Al día",
        ],
        "update.available": [
            .traditionalChinese: "可更新",
            .simplifiedChinese: "可更新",
            .english:  "available",
            .french:   "disponible",
            .japanese: "利用可能",
            .german:   "verfügbar",
            .spanish:  "disponible",
        ],
        "update.downloading": [
            .traditionalChinese: "正在下載…",
            .simplifiedChinese: "正在下载…",
            .english:  "Downloading…",
            .french:   "Téléchargement…",
            .japanese: "ダウンロード中…",
            .german:   "Wird geladen…",
            .spanish:  "Descargando…",
        ],
        "update.installing": [
            .traditionalChinese: "正在安裝…",
            .simplifiedChinese: "正在安装…",
            .english:  "Installing…",
            .french:   "Installation…",
            .japanese: "インストール中…",
            .german:   "Installiere…",
            .spanish:  "Instalando…",
        ],
        "update.install_btn": [
            .traditionalChinese: "下載更新",
            .simplifiedChinese: "下载更新",
            .english:  "Download",
            .french:   "Télécharger",
            .japanese: "ダウンロード",
            .german:   "Herunterladen",
            .spanish:  "Descargar",
        ],
        "update.error": [
            .traditionalChinese: "無法檢查更新",
            .simplifiedChinese: "无法检查更新",
            .english:  "Could not check for updates",
            .french:   "Impossible de vérifier les mises à jour",
            .japanese: "アップデートを確認できませんでした",
            .german:   "Konnte nicht auf Updates prüfen",
            .spanish:  "No se pudo verificar actualizaciones",
        ],

        // ── Wrapped ───────────────────────────────────────────────────────────
        "wrapped.btn": [
            .traditionalChinese: "✦ 你的相伴回顧",
            .simplifiedChinese: "✦ 你的陪伴回顾",
            .english:  "✦ Your Year in Numbers",
            .french:   "✦ Ton année en chiffres",
            .japanese: "✦ あなたの年間まとめ",
            .german:   "✦ Dein Jahr in Zahlen",
            .spanish:  "✦ Tu año en cifras",
        ],
        "wrapped.intro.eyebrow": [
            .traditionalChinese: "你的相伴回顧",
            .simplifiedChinese: "你的陪伴回顾",
            .english:  "YOUR YEAR IN NUMBERS",
            .french:   "TON ANNÉE EN CHIFFRES",
            .japanese: "今年を数字で振り返る",
            .german:   "DEIN JAHR IN ZAHLEN",
            .spanish:  "TU AÑO EN CIFRAS",
        ],
        "wrapped.intro.title": [
            .traditionalChinese: "這段日子，與你相伴的是",
            .simplifiedChinese: "一路相伴的是",
            .english:  "A year with",
            .french:   "Une année avec",
            .japanese: "と過ごした一年",
            .german:   "Ein Jahr mit",
            .spanish:  "Un año con",
        ],
        "wrapped.tap_hint": [
            .traditionalChinese: "點一下任意位置繼續",
            .simplifiedChinese: "点击任意位置继续",
            .english:  "Tap anywhere to continue",
            .french:   "Touche n'importe où pour continuer",
            .japanese: "タップして続ける",
            .german:   "Tippe irgendwo um fortzufahren",
            .spanish:  "Toca en cualquier lugar para continuar",
        ],

        // Distance
        "wrapped.distance.label": [
            .traditionalChinese: "一起走過的距離",
            .simplifiedChinese: "一起走过的距离",
            .english:  "YOU WALKED",
            .french:   "TU AS PARCOURU",
            .japanese: "一緒に歩いた距離",
            .german:   "IHR SEID GELAUFEN",
            .spanish:  "RECORRISTE",
        ],
        "wrapped.distance.phrase.0": [
            .traditionalChinese: "旅程才剛開始，每一步都值得紀念！",
            .simplifiedChinese: "旅程才刚开始，每一步都值得纪念！",
            .english:  "Just a few pixels walked. Every journey starts somewhere!",
            .french:   "À peine quelques pixels parcourus. Tout commence quelque part !",
            .japanese: "ほんの数ピクセル。すべての旅はここから始まる！",
            .german:   "Nur ein paar Pixel gelaufen. Jede Reise beginnt irgendwo!",
            .spanish:  "Solo unos píxeles. ¡Todo viaje empieza en algún lugar!",
        ],
        "wrapped.distance.phrase.1": [
            .traditionalChinese: "瞧，你帶著這隻小貓走了不少路呢！",
            .simplifiedChinese: "瞧，你带着这只小猫走了不少路呢！",
            .english:  "Look at you, actually walking this little cat!",
            .french:   "Dit donc, tu l'as fait marcher ce petit chat !",
            .japanese: "この小さな猫を歩かせたね！やるじゃないか！",
            .german:   "Schau an, du hast diese kleine Katze tatsächlich laufen lassen!",
            .spanish:  "¡Mira tú, haciendo caminar a este pequeño gato!",
        ],
        "wrapped.distance.phrase.2": [
            .traditionalChinese: "一起走過上千公尺，你們真是好搭檔。",
            .simplifiedChinese: "一起走过上千米，你们真是好搭档。",
            .english:  "Kilometers together. That's a real partnership.",
            .french:   "Des kilomètres ensemble. C'est une vraie équipe.",
            .japanese: "一緒にキロメートルを歩いた。本当のチームだ。",
            .german:   "Kilometer zusammen. Das ist echte Partnerschaft.",
            .spanish:  "Kilómetros juntos. Eso es una verdadera asociación.",
        ],
        "wrapped.distance.phrase.3": [
            .traditionalChinese: "真了不起。這隻小貓已經身經百戰了。",
            .simplifiedChinese: "真了不起。这只小猫已经身经百战了。",
            .english:  "Honestly? Impressive. This cat has earned its stripes.",
            .french:   "Franchement ? C'est impressionnant. Ce chat a bien gagné ses galons.",
            .japanese: "正直なところ？すごい。この猫は本当に頑張った。",
            .german:   "Ehrlich gesagt? Beeindruckend. Diese Katze hat ihre Sporen verdient.",
            .spanish:  "¿Honestamente? Impresionante. Este gato se ha ganado sus galones.",
        ],
        "wrapped.distance.phrase.4": [
            .traditionalChinese: "堪稱傳奇！這份默契，不必多說。",
            .simplifiedChinese: "堪称传奇！这份默契，无需多言。",
            .english:  "Legendary. Absolutely legendary. What else is there to say.",
            .french:   "Légendaire. Absolument légendaire. Que dire de plus.",
            .japanese: "伝説的。絶対に伝説的。もう何も言うことはない。",
            .german:   "Legendär. Absolut legendär. Was soll man da noch sagen.",
            .spanish:  "Legendario. Absolutamente legendario. Qué más se puede decir.",
        ],

        // Naps
        "wrapped.naps.label": [
            .traditionalChinese: "小睡次數",
            .simplifiedChinese: "小睡次数",
            .english:  "NAPS TAKEN",
            .french:   "SIESTES EFFECTUÉES",
            .japanese: "昼寝の回数",
            .german:   "NICKERCHEN GEMACHT",
            .spanish:  "SIESTAS REALIZADAS",
        ],
        "wrapped.naps.phrase.0": [
            .traditionalChinese: "小睡還不到五次，真是一隻勤奮的小貓。",
            .simplifiedChinese: "小睡还不到五次，真是一只勤快的小猫。",
            .english:  "Not even five naps. A truly dedicated cat.",
            .french:   "Même pas cinq siestes. Un chat de compétition.",
            .japanese: "5回も昼寝しなかった。本当に頑張り屋の猫だ。",
            .german:   "Nicht mal fünf Nickerchen. Eine wirklich engagierte Katze.",
            .spanish:  "Ni siquiera cinco siestas. Un gato verdaderamente dedicado.",
        ],
        "wrapped.naps.phrase.1": [
            .traditionalChinese: "睡得飽飽的小貓，才是開心的小貓。",
            .simplifiedChinese: "睡得饱饱的小猫，才是开心的小猫。",
            .english:  "A well-rested cat is a happy cat.",
            .french:   "Un chat bien reposé est un chat heureux.",
            .japanese: "よく休んだ猫は幸せな猫。",
            .german:   "Eine gut ausgeruhte Katze ist eine glückliche Katze.",
            .spanish:  "Un gato bien descansado es un gato feliz.",
        ],
        "wrapped.naps.phrase.2": [
            .traditionalChinese: "恭喜，已成為認證的小睡大師。",
            .simplifiedChinese: "恭喜，已成为认证的小睡大师。",
            .english:  "Certified expert in the noble art of napping.",
            .french:   "Expert certifié dans le noble art de la sieste.",
            .japanese: "昼寝という崇高な芸術の認定エキスパート。",
            .german:   "Zertifizierter Experte in der edlen Kunst des Nickerchens.",
            .spanish:  "Experto certificado en el noble arte de la siesta.",
        ],
        "wrapped.naps.phrase.3": [
            .traditionalChinese: "這隻小貓睡得比你還多。我們完全能理解。",
            .simplifiedChinese: "这只小猫睡得比你还多。我们表示理解。",
            .english:  "This cat sleeps more than you do. And we respect it.",
            .french:   "Ce chat dort probablement plus que toi. Et on respecte ça.",
            .japanese: "この猫はあなたより多く寝ている。そして、それを尊重する。",
            .german:   "Diese Katze schläft mehr als du. Und das respektieren wir.",
            .spanish:  "Este gato duerme más que tú. Y lo respetamos.",
        ],

        // Scratches
        "wrapped.scratches.label": [
            .traditionalChinese: "抓癢次數",
            .simplifiedChinese: "抓挠次数",
            .english:  "SCRATCHES",
            .french:   "GRIFFADES",
            .japanese: "引っかき回数",
            .german:   "KRATZER",
            .spanish:  "ARAÑAZOS",
        ],
        "wrapped.scratches.phrase.0": [
            .traditionalChinese: "小爪子很安分，真是一隻乖巧的小貓。",
            .simplifiedChinese: "小爪子很安分，真是一只乖巧的小猫。",
            .english:  "Your walls are immaculate. Well done.",
            .french:   "Tes murs sont impeccables. Bravo.",
            .japanese: "壁は完璧。よくやった。",
            .german:   "Deine Wände sind makellos. Gut gemacht.",
            .spanish:  "Tus paredes están impecables. Bien hecho.",
        ],
        "wrapped.scratches.phrase.1": [
            .traditionalChinese: "抓抓癢、伸伸爪，小貓也會照顧自己。",
            .simplifiedChinese: "挠挠痒、伸伸爪，小猫也会照顾自己。",
            .english:  "A few scratches. Nothing a lick of paint won't fix.",
            .french:   "Quelques griffures. Rien que la peinture ne peut pas cacher.",
            .japanese: "少し引っかき傷が。ペンキ一塗りで直るよ。",
            .german:   "Einige Kratzer. Nichts, was Farbe nicht richten kann.",
            .spanish:  "Algunos arañazos. Nada que una capa de pintura no solucione.",
        ],
        "wrapped.scratches.phrase.2": [
            .traditionalChinese: "抓癢這件事，小貓已經駕輕就熟。",
            .simplifiedChinese: "挠痒这件事，小猫已经轻车熟路。",
            .english:  "This cat has left its mark — literally.",
            .french:   "Ce chat a laissé sa marque — au sens propre.",
            .japanese: "この猫は文字通り、その痕跡を残した。",
            .german:   "Diese Katze hat ihre Spuren hinterlassen — buchstäblich.",
            .spanish:  "Este gato ha dejado su marca — literalmente.",
        ],
        "wrapped.scratches.phrase.3": [
            .traditionalChinese: "小爪子忙個不停，抓癢也是一門本事。",
            .simplifiedChinese: "小爪子忙个不停，挠痒也是一门手艺。",
            .english:  "Your walls have a soul now. We'd call it art.",
            .french:   "Tes murs ont une âme maintenant. On appelle ça de l'art.",
            .japanese: "壁に魂が宿った。これはアートと呼ぼう。",
            .german:   "Deine Wände haben jetzt eine Seele. Wir nennen das Kunst.",
            .spanish:  "Tus paredes tienen alma ahora. Lo llamaríamos arte.",
        ],

        // Days
        "wrapped.days.label": [
            .traditionalChinese: "相伴天數",
            .simplifiedChinese: "相伴天数",
            .english:  "DAYS TOGETHER",
            .french:   "JOURS ENSEMBLE",
            .japanese: "一緒に過ごした日数",
            .german:   "TAGE ZUSAMMEN",
            .spanish:  "DÍAS JUNTOS",
        ],
        "wrapped.days.phrase.0": [
            .traditionalChinese: "一段美好的冒險，才剛剛開始。",
            .simplifiedChinese: "一段美好的冒险，才刚刚开始。",
            .english:  "A beautiful adventure just getting started.",
            .french:   "Une belle aventure qui commence tout juste.",
            .japanese: "始まったばかりの美しい冒険。",
            .german:   "Ein wunderschönes Abenteuer, das gerade erst beginnt.",
            .spanish:  "Una hermosa aventura que apenas comienza.",
        ],
        "wrapped.days.phrase.1": [
            .traditionalChinese: "已經一週了？這隻小貓已經是家裡的一員了。",
            .simplifiedChinese: "已经一周了？这只小猫已经是家里的一员了。",
            .english:  "Already a week? This cat is part of the furniture now.",
            .french:   "Déjà une semaine ? Ce chat fait partie du décor maintenant.",
            .japanese: "もう一週間？この猫はもう家の一部だ。",
            .german:   "Schon eine Woche? Diese Katze gehört jetzt zum Inventar.",
            .spanish:  "¿Ya una semana? Este gato ya forma parte del mobiliario.",
        ],
        "wrapped.days.phrase.2": [
            .traditionalChinese: "相伴已滿 30 天，你們已經是有默契的室友了。",
            .simplifiedChinese: "相伴已满 30 天，你们已经是默契的室友了。",
            .english:  "A month and more together. A real cohabitation.",
            .french:   "Un mois et plus ensemble. Une vraie colocation.",
            .japanese: "一ヶ月以上一緒に。本当の共同生活だ。",
            .german:   "Ein Monat und mehr zusammen. Eine echte Wohngemeinschaft.",
            .spanish:  "Un mes y más juntos. Una verdadera convivencia.",
        ],
        "wrapped.days.phrase.3": [
            .traditionalChinese: "相伴已滿百天，這隻小貓早已把你放在心上。",
            .simplifiedChinese: "相伴已满百天，这只小猫早已把你放在心上。",
            .english:  "Almost a year. This cat knows you by heart.",
            .french:   "Presque un an. Ce chat te connaît par cœur.",
            .japanese: "もうすぐ一年。この猫はあなたのことを熟知している。",
            .german:   "Fast ein Jahr. Diese Katze kennt dich in- und auswendig.",
            .spanish:  "Casi un año. Este gato te conoce de memoria.",
        ],
        "wrapped.days.phrase.4": [
            .traditionalChinese: "相伴已滿 365 天，正式宣布：你們形影不離。",
            .simplifiedChinese: "相伴已满 365 天，正式宣布：你们形影不离。",
            .english:  "A year and more. Official: you two are inseparable.",
            .french:   "Un an et plus. Officiel : vous êtes inséparables.",
            .japanese: "一年以上。公式発表：あなたたちは切っても切れない仲だ。",
            .german:   "Ein Jahr und mehr. Offiziell: Ihr seid unzertrennlich.",
            .spanish:  "Un año y más. Oficial: son inseparables.",
        ],

        // Outro
        "wrapped.outro.title": [
            .traditionalChinese: "明天見 ✦",
            .simplifiedChinese: "明天见 ✦",
            .english:  "See you tomorrow ✦",
            .french:   "À demain ✦",
            .japanese: "また明日 ✦",
            .german:   "Bis morgen ✦",
            .spanish:  "Hasta mañana ✦",
        ],
        "wrapped.outro.sub": [
            .traditionalChinese: "你的小貓會一直在這裡。",
            .simplifiedChinese: "你的小猫会一直在这里。",
            .english:  "Your little cat will be here.",
            .french:   "Ton petit chat sera là.",
            .japanese: "あなたの小さな猫がここにいるよ。",
            .german:   "Deine kleine Katze wird da sein.",
            .spanish:  "Tu pequeño gato estará aquí.",
        ],
        "wrapped.close": [
            .traditionalChinese: "關閉",
            .simplifiedChinese: "关闭",
            .english:  "Close",
            .french:   "Fermer",
            .japanese: "閉じる",
            .german:   "Schließen",
            .spanish:  "Cerrar",
        ],

        // ── v3 additions ──────────────────────────────────────────────────────
        "ob.card.share": [
            .traditionalChinese: "分享我的卡片",
            .simplifiedChinese: "分享我的卡片",
            .english:  "Share my card",
            .french:   "Partager ma carte",
            .japanese: "カードをシェア",
            .german:   "Karte teilen",
            .spanish:  "Compartir tarjeta",
        ],
        "settings.launch_login": [
            .traditionalChinese: "登入時啟動",
            .simplifiedChinese: "登录时启动",
            .english:  "Launch at login",
            .french:   "Lancer au démarrage",
            .japanese: "ログイン時に起動",
            .german:   "Bei Anmeldung starten",
            .spanish:  "Iniciar al arranque",
        ],
        "settings.size": [
            .traditionalChinese: "大小",
            .simplifiedChinese: "大小",
            .english:  "Size",
            .french:   "Taille",
            .japanese: "サイズ",
            .german:   "Größe",
            .spanish:  "Tamaño",
        ],
        "settings.speed": [
            .traditionalChinese: "速度",
            .simplifiedChinese: "速度",
            .english:  "Speed",
            .french:   "Vitesse",
            .japanese: "スピード",
            .german:   "Geschwindigkeit",
            .spanish:  "Velocidad",
        ],
        "settings.your_pet": [
            .traditionalChinese: "你的寵物",
            .simplifiedChinese: "你的宠物",
            .english:  "Your pet",
            .french:   "Votre pet",
            .japanese: "あなたのペット",
            .german:   "Dein Haustier",
            .spanish:  "Tu mascota",
        ],
        "settings.achievements": [
            .traditionalChinese: "成就",
            .simplifiedChinese: "成就",
            .english:  "Achievements",
            .french:   "Succès",
            .japanese: "実績",
            .german:   "Erfolge",
            .spanish:  "Logros",
        ],

        // ── Shared labels and complete formatted phrases ───────────────────────
        "menu.laser": [
            .traditionalChinese: "雷射逗貓",
            .english: "Laser Pointer",
            .simplifiedChinese: "激光逗猫",
        ],
        "menu.settings": [
            .traditionalChinese: "設定",
            .english: "Settings",
            .simplifiedChinese: "设置",
        ],
        "settings.personalize": [
            .traditionalChinese: "個人化",
            .english: "PERSONALIZE",
            .simplifiedChinese: "个性化",
        ],
        "settings.made_with_love": [
            .traditionalChinese: "用心製作 ❤️",
            .english: "Made with ❤️ by",
            .simplifiedChinese: "用心制作 ❤️",
        ],
        "stats.level": [
            .traditionalChinese: "%d 級",
            .english: "Lv.%d",
            .simplifiedChinese: "%d 级",
        ],
        "stats.day_streak": [
            .traditionalChinese: "連續啟動（天）",
            .english: "day streak",
            .simplifiedChinese: "连续启动（天）",
        ],
        "stats.walked_distance": [
            .traditionalChinese: "已走 %d 公尺",
            .english: "%dm walked",
            .french: "%dm parcourus",
            .japanese: "%dm 歩いた",
            .german: "%dm gelaufen",
            .spanish: "%dm recorridos",
            .simplifiedChinese: "已走 %d 米",
        ],
        "stats.next_level": [
            .traditionalChinese: "再走 %.0f 公尺升至 %d 級",
            .english: "%.0fm to Lv.%d",
            .simplifiedChinese: "再走 %.0f 米升至 %d 级",
        ],
        "stats.xp_progress": [
            .traditionalChinese: "%d 公尺 / %d 公尺",
            .english: "%dm / %dm",
            .simplifiedChinese: "%d 米 / %d 米",
        ],
        "distance.meters": [
            .traditionalChinese: "%.0f 公尺",
            .english: "%.0f m",
            .simplifiedChinese: "%.0f 米",
        ],
        "distance.kilometers": [
            .traditionalChinese: "%.1f 公里",
            .english: "%.1f km",
            .simplifiedChinese: "%.1f 公里",
        ],
        "update.archive_invalid": [
            .traditionalChinese: "更新安裝檔無效",
            .english: "Archive invalid",
            .simplifiedChinese: "更新安装包无效",
        ],
        "personality.custom": [
            .english: "Unique & full of surprises",
            .simplifiedChinese: "独特又充满惊喜",
            .traditionalChinese: "獨特又充滿驚喜",
        ],
        "speed.slow": [
            .english: "Lazy (0.4×)",
            .simplifiedChinese: "慵懒（0.4×）",
            .traditionalChinese: "慵懶（0.4×）",
        ],
        "speed.normal": [
            .english: "Normal (1×)",
            .simplifiedChinese: "标准（1×）",
            .traditionalChinese: "標準（1×）",
        ],
        "speed.fast": [
            .english: "Hyper (2.5×)",
            .simplifiedChinese: "极速（2.5×）",
            .traditionalChinese: "極速（2.5×）",
        ],
        "update.install_error": [
            .english: "Couldn't install the update. Please try again.",
            .simplifiedChinese: "更新安装失败，请重试。",
            .traditionalChinese: "更新安裝失敗，請重試。",
        ],
        "marketplace.error_detail": [
            .english: "Please try again later.",
            .simplifiedChinese: "请稍后重试。",
            .traditionalChinese: "請稍後再試。",
        ],
        "settings.custom_pet": [
            .simplifiedChinese: "用照片生成", .traditionalChinese: "用照片生成", .english: "From photos",
            .french: "Depuis des photos", .japanese: "写真から作る", .german: "Aus Fotos", .spanish: "Desde fotos",
        ],
        "marketplace.custom_pet": [
            .simplifiedChinese: "用照片生成我的宠物", .traditionalChinese: "用照片生成我的寵物", .english: "Create a pet from photos",
            .french: "Créer un pet à partir de photos", .japanese: "写真からペットを作る", .german: "Pet aus Fotos erzeugen", .spanish: "Crear una mascota con fotos",
        ],
        "custompet.title": [
            .simplifiedChinese: "我的宠物", .traditionalChinese: "我的寵物", .english: "Your pet",
            .french: "Votre pet", .japanese: "マイペット", .german: "Dein Pet", .spanish: "Tu mascota",
        ],
        "custompet.subtitle": [
            .simplifiedChinese: "用 3–5 张照片生成一只桌宠", .traditionalChinese: "用 3–5 張照片生成一隻桌寵", .english: "Turn 3–5 photos into a desktop pet",
            .french: "3 à 5 photos deviennent un pet", .japanese: "写真 3–5 枚からデスクトップペットを作ります", .german: "Aus 3–5 Fotos ein Desktop-Pet machen", .spanish: "Convierte 3–5 fotos en una mascota",
        ],
        "custompet.your_pets": [
            .simplifiedChinese: "已保存", .traditionalChinese: "已儲存", .english: "Saved pets",
            .french: "Pets enregistrés", .japanese: "保存済み", .german: "Gespeicherte Pets", .spanish: "Mascotas guardadas",
        ],
        "custompet.empty": [
            .simplifiedChinese: "还没有自定义宠物。", .traditionalChinese: "還沒有自訂寵物。", .english: "No custom pets yet.",
            .french: "Pas encore de pet personnalisé.", .japanese: "まだカスタムペットはありません。", .german: "Noch keine eigenen Pets.", .spanish: "Aún no hay mascotas propias.",
        ],
        "custompet.choose_photos": [
            .simplifiedChinese: "选择照片", .traditionalChinese: "選擇照片", .english: "Choose photos",
            .french: "Choisir des photos", .japanese: "写真を選ぶ", .german: "Fotos wählen", .spanish: "Elegir fotos",
        ],
        "custompet.photo_hint": [
            .simplifiedChinese: "请选同一只宠物的 3–5 张清晰照片，尽量包含正面、侧面和全身。", .traditionalChinese: "請選同一隻寵物的 3–5 張清晰照片，盡量包含正面、側面和全身。", .english: "Use 3–5 clear photos of the same pet: front, side, and full body.",
            .french: "3 à 5 photos nettes du même animal : face, profil et corps entier.", .japanese: "同じペットの正面、横、全身が分かる鮮明な写真を 3–5 枚。", .german: "3–5 scharfe Fotos desselben Tiers: vorne, seitlich und ganzkörperlich.", .spanish: "3–5 fotos nítidas de la misma mascota: frente, perfil y cuerpo entero.",
        ],
        "custompet.quadruped_note": [
            .simplifiedChinese: "动作和现有桌宠一样：八方向走路、坐下、挠痒和睡觉，最适合猫狗这类四足动物。", .traditionalChinese: "動作和現有桌寵一樣：八方向走路、坐下、撓癢和睡覺，最適合貓狗這類四足動物。", .english: "Poses match the current pets: walk in 8 directions, sit, scratch, and sleep. Cats and dogs fit best.",
            .french: "Les poses suivent les pets actuels : marche à 8 directions, assis, grattage et sommeil. Chats et chiens conviennent le mieux.", .japanese: "動きは今のペットと同じです。8 方向の歩行、座り、掻く、眠る。猫と犬に向いています。", .german: "Die Posen entsprechen den vorhandenen Pets: 8 Laufrichtungen, sitzen, kratzen, schlafen. Katzen und Hunde passen am besten.", .spanish: "Las poses son las de las mascotas actuales: caminar en 8 direcciones, sentarse, rascarse y dormir. Encajan mejor gatos y perros.",
        ],
        "custompet.name": [
            .simplifiedChinese: "名字", .traditionalChinese: "名字", .english: "Name",
            .french: "Nom", .japanese: "名前", .german: "Name", .spanish: "Nombre",
        ],
        "custompet.generate": [
            .simplifiedChinese: "生成", .traditionalChinese: "生成", .english: "Generate",
            .french: "Générer", .japanese: "生成", .german: "Erzeugen", .spanish: "Generar",
        ],
        "custompet.retry_failed": [
            .simplifiedChinese: "重试失败的帧", .traditionalChinese: "重試失敗的幀", .english: "Retry failed frames",
            .french: "Réessayer les images échouées", .japanese: "失敗したフレームを再試行", .german: "Fehlgeschlagene Frames erneut", .spanish: "Reintentar fotogramas fallidos",
        ],
        "custompet.start_over": [
            .simplifiedChinese: "全部重来", .traditionalChinese: "全部重來", .english: "Start over",
            .french: "Tout recommencer", .japanese: "最初から", .german: "Neu beginnen", .spanish: "Empezar de nuevo",
        ],
        "custompet.save": [
            .simplifiedChinese: "保存并使用", .traditionalChinese: "儲存並使用", .english: "Save and use",
            .french: "Enregistrer et utiliser", .japanese: "保存して使う", .german: "Sichern und verwenden", .spanish: "Guardar y usar",
        ],
        "custompet.delete": [
            .simplifiedChinese: "删除", .traditionalChinese: "刪除", .english: "Delete",
            .french: "Supprimer", .japanese: "削除", .german: "Löschen", .spanish: "Eliminar",
        ],
        "custompet.use": [
            .simplifiedChinese: "使用", .traditionalChinese: "使用", .english: "Use",
            .french: "Utiliser", .japanese: "使う", .german: "Nutzen", .spanish: "Usar",
        ],
        "custompet.cancel": [
            .simplifiedChinese: "取消", .traditionalChinese: "取消", .english: "Cancel",
            .french: "Annuler", .japanese: "キャンセル", .german: "Abbrechen", .spanish: "Cancelar",
        ],
        "custompet.back": [
            .simplifiedChinese: "返回", .traditionalChinese: "返回", .english: "Back",
            .french: "Retour", .japanese: "戻る", .german: "Zurück", .spanish: "Volver",
        ],
        "custompet.api_key": [
            .simplifiedChinese: "API 密钥", .traditionalChinese: "API 金鑰", .english: "API key",
            .french: "Clé API", .japanese: "API キー", .german: "API-Schlüssel", .spanish: "Clave API",
        ],
        "custompet.api_key_placeholder": [
            .simplifiedChinese: "sk-…", .traditionalChinese: "sk-…", .english: "sk-…",
            .french: "sk-…", .japanese: "sk-…", .german: "sk-…", .spanish: "sk-…",
        ],
        "custompet.api_key_save": [
            .simplifiedChinese: "保存到钥匙串", .traditionalChinese: "儲存到鑰匙圈", .english: "Save key in Keychain",
            .french: "Enregistrer dans le Trousseau", .japanese: "キーチェーンに保存", .german: "Im Schlüsselbund sichern", .spanish: "Guardar en el Llavero",
        ],
        "custompet.api_key_saved": [
            .simplifiedChinese: "钥匙串里已有密钥。", .traditionalChinese: "鑰匙圈裡已有金鑰。", .english: "A key is saved in Keychain.",
            .french: "Une clé est dans le Trousseau.", .japanese: "キーチェーンにキーがあります。", .german: "Ein Schlüssel liegt im Schlüsselbund.", .spanish: "Hay una clave en el Llavero.",
        ],
        "custompet.api_key_missing": [
            .simplifiedChinese: "生成前请先保存 API 密钥。", .traditionalChinese: "生成前請先儲存 API 金鑰。", .english: "Add an API key before generating.",
            .french: "Ajoutez une clé API avant de générer.", .japanese: "生成する前に API キーを保存してください。", .german: "Vor dem Erzeugen einen API-Schlüssel sichern.", .spanish: "Añade una clave API antes de generar.",
        ],
        "custompet.api_key_clear": [
            .simplifiedChinese: "移除密钥", .traditionalChinese: "移除金鑰", .english: "Remove key",
            .french: "Retirer la clé", .japanese: "キーを削除", .german: "Schlüssel entfernen", .spanish: "Quitar clave",
        ],
        "custompet.api_key_error": [
            .simplifiedChinese: "无法写入钥匙串。", .traditionalChinese: "無法寫入鑰匙圈。", .english: "Could not update Keychain.",
            .french: "Impossible de modifier le Trousseau.", .japanese: "キーチェーンを更新できません。", .german: "Schlüsselbund konnte nicht aktualisiert werden.", .spanish: "No se pudo actualizar el Llavero.",
        ],
        "custompet.model": [
            .simplifiedChinese: "模型", .traditionalChinese: "模型", .english: "Model",
            .french: "Modèle", .japanese: "モデル", .german: "Modell", .spanish: "Modelo",
        ],
        "custompet.base_url": [
            .simplifiedChinese: "接口地址", .traditionalChinese: "介面位址", .english: "API base URL",
            .french: "URL de base de l'API", .japanese: "API のベース URL", .german: "API-Basis-URL", .spanish: "URL base de la API",
        ],
        "custompet.quality": [
            .simplifiedChinese: "画质", .traditionalChinese: "畫質", .english: "Quality",
            .french: "Qualité", .japanese: "品質", .german: "Qualität", .spanish: "Calidad",
        ],
        "custompet.quality.low": [
            .simplifiedChinese: "低", .traditionalChinese: "低", .english: "Low",
            .french: "Basse", .japanese: "低", .german: "Niedrig", .spanish: "Baja",
        ],
        "custompet.quality.medium": [
            .simplifiedChinese: "中", .traditionalChinese: "中", .english: "Medium",
            .french: "Moyenne", .japanese: "中", .german: "Mittel", .spanish: "Media",
        ],
        "custompet.quality.high": [
            .simplifiedChinese: "高", .traditionalChinese: "高", .english: "High",
            .french: "Haute", .japanese: "高", .german: "Hoch", .spanish: "Alta",
        ],
        "custompet.include_walk": [
            .simplifiedChinese: "四帧步态（更顺，请求更多）", .traditionalChinese: "四幀步態（更順，請求更多）", .english: "Four-frame walk (smoother, more requests)",
            .french: "Marche en quatre images (plus fluide, plus de requêtes)", .japanese: "4 フレーム歩行（滑らか、リクエスト増）", .german: "Vier-Frame-Gang (flüssiger, mehr Anfragen)", .spanish: "Paso de cuatro fotogramas (más fluido, más solicitudes)",
        ],
        "custompet.cost_estimate": [
            .simplifiedChinese: "约 $%.2f（%d 次图像请求）。实际费用以服务商标价为准。", .traditionalChinese: "約 $%.2f（%d 次圖像請求）。實際費用以服務商標價為準。", .english: "About $%.2f for %d images. Provider pricing applies.",
            .french: "Environ $%.2f pour %d images. Le tarif du fournisseur s'applique.", .japanese: "約 $%.2f（画像 %d 回）。料金は提供者の価格に従います。", .german: "Etwa $%.2f für %d Bilder. Es gilt der Preis des Anbieters.", .spanish: "Unos $%.2f por %d imágenes. Se aplica el precio del proveedor.",
        ],
        "custompet.privacy": [
            .simplifiedChinese: "照片只发给这把密钥对应的服务商，飘伴不会保存照片。", .traditionalChinese: "照片只發給這把金鑰對應的服務商，飄伴不會保存照片。", .english: "Photos go only to the provider for this key. PiaoPal does not save them.",
            .french: "Les photos vont seulement au fournisseur de cette clé. PiaoPal ne les enregistre pas.", .japanese: "写真はこのキーの提供者にだけ送られます。PiaoPal は写真を保存しません。", .german: "Fotos gehen nur an den Anbieter dieses Schlüssels. PiaoPal speichert sie nicht.", .spanish: "Las fotos solo van al proveedor de esta clave. PiaoPal no las guarda.",
        ],
        "custompet.preview": [
            .simplifiedChinese: "预览", .traditionalChinese: "預覽", .english: "Preview",
            .french: "Aperçu", .japanese: "プレビュー", .german: "Vorschau", .spanish: "Vista previa",
        ],
        "custompet.delete_confirm": [
            .simplifiedChinese: "删除这只宠物？", .traditionalChinese: "刪除這隻寵物？", .english: "Delete this pet?",
            .french: "Supprimer ce pet ?", .japanese: "このペットを削除しますか？", .german: "Dieses Pet löschen?", .spanish: "¿Eliminar esta mascota?",
        ],
        "custompet.default_name": [
            .simplifiedChinese: "我的宠物", .traditionalChinese: "我的寵物", .english: "My pet",
            .french: "Mon pet", .japanese: "マイペット", .german: "Mein Pet", .spanish: "Mi mascota",
        ],
        "custompet.progress.reference": [
            .simplifiedChinese: "正在画角色参考", .traditionalChinese: "正在畫角色參考", .english: "Drawing the character reference",
            .french: "Dessin de la référence", .japanese: "キャラクター参考を描いています", .german: "Charakterreferenz wird gezeichnet", .spanish: "Dibujando la referencia",
        ],
        "custompet.progress.frame": [
            .simplifiedChinese: "第 %d 帧，共 %d 帧", .traditionalChinese: "第 %d 幀，共 %d 幀", .english: "Frame %d of %d",
            .french: "Image %d sur %d", .japanese: "%d / %d フレーム", .german: "Frame %d von %d", .spanish: "Fotograma %d de %d",
        ],
        "custompet.issue.too_few": [
            .simplifiedChinese: "至少选择 %d 张照片（当前 %d 张）。", .traditionalChinese: "至少選擇 %d 張照片（目前 %d 張）。", .english: "Choose at least %d photos (%d selected).",
            .french: "Choisissez au moins %d photos (%d sélectionnées).", .japanese: "写真は少なくとも %d 枚必要です（現在 %d 枚）。", .german: "Mindestens %d Fotos wählen (%d ausgewählt).", .spanish: "Elige al menos %d fotos (%d seleccionadas).",
        ],
        "custompet.issue.too_many": [
            .simplifiedChinese: "最多选择 %d 张照片（当前 %d 张）。", .traditionalChinese: "最多選擇 %d 張照片（目前 %d 張）。", .english: "Choose at most %d photos (%d selected).",
            .french: "Choisissez au plus %d photos (%d sélectionnées).", .japanese: "写真は最大 %d 枚です（現在 %d 枚）。", .german: "Höchstens %d Fotos wählen (%d ausgewählt).", .spanish: "Elige como máximo %d fotos (%d seleccionadas).",
        ],
        "custompet.issue.unreadable": [
            .simplifiedChinese: "无法读取这张图片。", .traditionalChinese: "無法讀取這張圖片。", .english: "Could not read this image.",
            .french: "Impossible de lire cette image.", .japanese: "この画像を読み取れません。", .german: "Dieses Bild konnte nicht gelesen werden.", .spanish: "No se pudo leer esta imagen.",
        ],
        "custompet.issue.unsupported": [
            .simplifiedChinese: "请使用 JPEG、PNG、HEIC、WebP、GIF 或 TIFF。", .traditionalChinese: "請使用 JPEG、PNG、HEIC、WebP、GIF 或 TIFF。", .english: "Use a JPEG, PNG, HEIC, WebP, GIF, or TIFF.",
            .french: "Utilisez un JPEG, PNG, HEIC, WebP, GIF ou TIFF.", .japanese: "JPEG、PNG、HEIC、WebP、GIF、TIFF を使ってください。", .german: "Bitte JPEG, PNG, HEIC, WebP, GIF oder TIFF verwenden.", .spanish: "Usa JPEG, PNG, HEIC, WebP, GIF o TIFF.",
        ],
        "custompet.issue.too_large": [
            .simplifiedChinese: "文件超过 25 MB。", .traditionalChinese: "檔案超過 25 MB。", .english: "This file is larger than 25 MB.",
            .french: "Ce fichier dépasse 25 Mo.", .japanese: "ファイルが 25 MB を超えています。", .german: "Diese Datei ist größer als 25 MB.", .spanish: "Este archivo supera los 25 MB.",
        ],
        "custompet.issue.too_small": [
            .simplifiedChinese: "短边至少 %d 像素（这张是 %d）。", .traditionalChinese: "短邊至少 %d 像素（這張是 %d）。", .english: "The short side must be at least %d px (this one is %d).",
            .french: "Le petit côté doit faire au moins %d px (celui-ci fait %d).", .japanese: "短辺は %d px 以上必要です（この写真は %d）。", .german: "Die kurze Seite muss mindestens %d px haben (diese hat %d).", .spanish: "El lado corto debe tener al menos %d px (este tiene %d).",
        ],
        "custompet.issue.aspect": [
            .simplifiedChinese: "请裁到长边不超过短边的 3 倍。", .traditionalChinese: "請裁到長邊不超過短邊的 3 倍。", .english: "Crop it so the long side is at most 3× the short side.",
            .french: "Recadrez pour que le grand côté fasse au plus 3 fois le petit.", .japanese: "長辺が短辺の 3 倍以内になるように切り抜いてください。", .german: "Zuschneiden, sodass die lange Seite höchstens 3× die kurze ist.", .spanish: "Recorta para que el lado largo sea como máximo 3 veces el corto.",
        ],
        "custompet.issue.blurry": [
            .simplifiedChinese: "这张照片太模糊。", .traditionalChinese: "這張照片太模糊。", .english: "This photo looks too blurry.",
            .french: "Cette photo est trop floue.", .japanese: "この写真はぼやけすぎています。", .german: "Dieses Foto ist zu unscharf.", .spanish: "Esta foto se ve demasiado borrosa.",
        ],
        "custompet.issue.empty": [
            .simplifiedChinese: "看不清主体。", .traditionalChinese: "看不清主體。", .english: "No clear subject in this photo.",
            .french: "Pas de sujet net dans cette photo.", .japanese: "被写体がはっきりしません。", .german: "Kein klares Motiv in diesem Foto.", .spanish: "No hay un sujeto claro en esta foto.",
        ],
        "custompet.error.no_key": [
            .simplifiedChinese: "请先保存 API 密钥。", .traditionalChinese: "請先儲存 API 金鑰。", .english: "Save an API key first.",
            .french: "Enregistrez d'abord une clé API.", .japanese: "先に API キーを保存してください。", .german: "Zuerst einen API-Schlüssel sichern.", .spanish: "Guarda primero una clave API.",
        ],
        "custompet.error.settings": [
            .simplifiedChinese: "请检查模型名称和接口地址。", .traditionalChinese: "請檢查模型名稱和介面位址。", .english: "Check the model name and API base URL.",
            .french: "Vérifiez le modèle et l'URL de l'API.", .japanese: "モデル名と API の URL を確認してください。", .german: "Modellname und API-Basis-URL prüfen.", .spanish: "Revisa el modelo y la URL base de la API.",
        ],
        "custompet.error.moderation": [
            .simplifiedChinese: "服务商拒绝了这次请求。", .traditionalChinese: "服務商拒絕了這次請求。", .english: "The provider declined this request.",
            .french: "Le fournisseur a refusé cette demande.", .japanese: "提供者がこのリクエストを拒否しました。", .german: "Der Anbieter hat diese Anfrage abgelehnt.", .spanish: "El proveedor rechazó esta solicitud.",
        ],
        "custompet.error.network": [
            .simplifiedChinese: "网络请求失败，可以重试。", .traditionalChinese: "網路請求失敗，可以重試。", .english: "The network request failed. You can retry.",
            .french: "La requête réseau a échoué. Vous pouvez réessayer.", .japanese: "通信に失敗しました。再試行できます。", .german: "Die Netzwerkanfrage ist fehlgeschlagen. Erneut versuchen ist möglich.", .spanish: "Falló la solicitud de red. Puedes reintentar.",
        ],
        "custompet.error.provider": [
            .simplifiedChinese: "图像服务返回了错误。", .traditionalChinese: "影像服務傳回了錯誤。", .english: "The image provider returned an error.",
            .french: "Le fournisseur d'images a renvoyé une erreur.", .japanese: "画像サービスがエラーを返しました。", .german: "Der Bildanbieter hat einen Fehler gemeldet.", .spanish: "El proveedor de imágenes devolvió un error.",
        ],
        "custompet.error.validation": [
            .simplifiedChinese: "这些帧还需要重试：%@", .traditionalChinese: "這些幀還需要重試：%@", .english: "Some frames still need another try: %@",
            .french: "Certaines images doivent être refaites : %@", .japanese: "これらのフレームは再試行が必要です：%@", .german: "Diese Frames brauchen einen weiteren Versuch: %@", .spanish: "Estos fotogramas necesitan otro intento: %@",
        ],
        "custompet.error.save": [
            .simplifiedChinese: "无法保存这只宠物。", .traditionalChinese: "無法儲存這隻寵物。", .english: "Could not save the pet.",
            .french: "Impossible d'enregistrer le pet.", .japanese: "ペットを保存できません。", .german: "Das Pet konnte nicht gesichert werden.", .spanish: "No se pudo guardar la mascota.",
        ],
        "custompet.error.cancelled": [
            .simplifiedChinese: "生成已取消。", .traditionalChinese: "生成已取消。", .english: "Generation was cancelled.",
            .french: "La génération a été annulée.", .japanese: "生成をキャンセルしました。", .german: "Die Erzeugung wurde abgebrochen.", .spanish: "Se canceló la generación.",
        ],
    ]
}
