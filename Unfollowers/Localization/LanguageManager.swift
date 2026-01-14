import Foundation

enum AppLanguage: String, CaseIterable {
    case en
    case tr

    static func fromSystem() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("tr") ? .tr : .en
    }
}

final class LanguageManager: ObservableObject {
    private let storageKey = "app.language"

    @Published var currentLanguage: AppLanguage {
        didSet {
            persist(currentLanguage)
            Bundle.setLanguage(currentLanguage.rawValue)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: raw) {
            currentLanguage = lang
        } else {
            let system = AppLanguage.fromSystem()
            currentLanguage = system
        }
        Bundle.setLanguage(currentLanguage.rawValue)
    }

    private func persist(_ lang: AppLanguage) {
        UserDefaults.standard.set(lang.rawValue, forKey: storageKey)
    }
}
