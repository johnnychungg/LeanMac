// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

// MARK: - Languages

/// Languages the UI is translated into. English is the source language (the text written in code);
/// every other language is a `<code>.lproj/Localizable.strings` file (see `App/Bundle/Localization`).
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en
    case vi

    public var id: String { rawValue }
    public var code: String { rawValue }

    /// First-run default: the first system-preferred language we translate, otherwise English.
    public static func systemDefault(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for tag in preferred {
            let base = tag.split(separator: "-").first.map(String.init) ?? tag
            if let match = AppLanguage(rawValue: base) { return match }
        }
        return .en
    }

    /// Name shown in the language picker, always written in the language itself.
    public var displayName: String {
        switch self {
        case .en: return "English"
        case .vi: return "Tiếng Việt"
        }
    }
}

// MARK: - Localization key (supports string interpolation)

/// The argument of `tr(_:)`. Interpolations (`\(value)`) become `%@` placeholders so the translation
/// can reorder them (`%2$@ … %1$@`). A literal percent sign is stored as `%%`.
public struct L10nKey: ExpressibleByStringInterpolation, Sendable {
    public let format: String
    public let args: [String]

    public init(stringLiteral value: String) {
        format = value.replacingOccurrences(of: "%", with: "%%")
        args = []
    }

    public init(stringInterpolation interpolation: Interpolation) {
        format = interpolation.format
        args = interpolation.args
    }

    public struct Interpolation: StringInterpolationProtocol {
        var format = ""
        var args: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            format += literal.replacingOccurrences(of: "%", with: "%%")
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            format += "%@"
            args.append("\(value)")
        }
    }
}

// MARK: - Runtime lookup

/// Thread-safe translation state. Pure Foundation so every layer can call `tr(_:)`.
public enum L10n {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        // Read the saved choice right away so strings built before LanguageManager exists are already correct.
        var languageCode = UserDefaults.standard.string(forKey: "jmac_app_language") ?? AppLanguage.systemDefault().code
        var bundles: [String: Bundle?] = [:]
        var searchBundle: Bundle = .main
    }
    private static let state = State()
    private static var lock: NSLock { state.lock }

    /// Where `<code>.lproj` folders are looked up (the app's `Contents/Resources`). Tests may override it.
    public static func setResourceBundle(_ bundle: Bundle) {
        lock.lock(); defer { lock.unlock() }
        state.searchBundle = bundle
        state.bundles = [:]
    }

    public static func setLanguage(_ language: AppLanguage) {
        lock.lock(); defer { lock.unlock() }
        state.languageCode = language.code
    }

    public static func translate(_ key: L10nKey) -> String {
        lock.lock()
        let code = state.languageCode
        var template = key.format
        if code != AppLanguage.en.code {
            let bundle: Bundle?
            if let cached = state.bundles[code] {
                bundle = cached
            } else {
                bundle = state.searchBundle.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
                state.bundles[code] = .some(bundle)
            }
            if let bundle {
                template = bundle.localizedString(forKey: key.format, value: key.format, table: nil)
            }
        }
        lock.unlock()
        return substitute(template, key.args)
    }

    /// Replaces `%@`, `%N$@` and `%%`. Never crashes on a malformed translation.
    package static func substitute(_ template: String, _ args: [String]) -> String {
        guard template.contains("%") else { return template }
        var out = ""
        var next = 0
        let chars = Array(template)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "%", i + 1 < chars.count else { out.append(c); i += 1; continue }
            let n = chars[i + 1]
            if n == "%" { out.append("%"); i += 2; continue }
            if n == "@" {
                if next < args.count { out += args[next] }
                next += 1
                i += 2
                continue
            }
            // %N$@
            var j = i + 1
            var digits = ""
            while j < chars.count, chars[j].isNumber { digits.append(chars[j]); j += 1 }
            if !digits.isEmpty, j + 1 < chars.count, chars[j] == "$", chars[j + 1] == "@", let index = Int(digits) {
                if index >= 1, index <= args.count { out += args[index - 1] }
                i = j + 2
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }
}

/// Translates UI text. The argument is the English source text; the active language decides the result.
@inline(__always)
public func tr(_ key: L10nKey) -> String {
    L10n.translate(key)
}

// MARK: - Language preference (observable)

public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    private let storageKey = "jmac_app_language"

    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: storageKey)
            L10n.setLanguage(currentLanguage)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:))
        // First run follows the system language (en or vi); a user choice is remembered.
        let language = saved ?? AppLanguage.systemDefault()
        currentLanguage = language
        L10n.setLanguage(language)
    }

    public var nextLanguage: AppLanguage {
        let all = AppLanguage.allCases
        let index = all.firstIndex(of: currentLanguage) ?? 0
        return all[(index + 1) % all.count]
    }

    public func switchLanguage(to language: AppLanguage) {
        currentLanguage = language
    }

    public func toggleLanguage() {
        currentLanguage = nextLanguage
    }

    /// Switches immediately, without a confirmation dialog.
    public func promptLanguageSwitch() {
        toggleLanguage()
    }
}
