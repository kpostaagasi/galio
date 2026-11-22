import Foundation

/// Localisation helpers. Turkish is the development language: keys in `Localizable.xcstrings`
/// are the Turkish strings, English translations live in the catalog.
/// SwiftUI `Text("…")` literals are localised automatically; `Loc.tr` covers runtime strings.
enum Loc {
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
    }

    /// True when the UI runs in Turkish (affects champion/item names from the data set).
    static var isTurkish: Bool {
        (Bundle.main.preferredLocalizations.first ?? "tr").hasPrefix("tr")
    }

    static func pick(tr: String, en: String) -> String { isTurkish ? tr : en }

    /// Language override written to the app's `AppleLanguages` default (applies after relaunch).
    static let languageDefaultsKey = "appLanguage"

    static func applyLanguageOverride(_ code: String) {
        let defaults = UserDefaults.standard
        switch code {
        case "tr", "en": defaults.set([code], forKey: "AppleLanguages")
        default: defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.set(code, forKey: languageDefaultsKey)
    }
}
