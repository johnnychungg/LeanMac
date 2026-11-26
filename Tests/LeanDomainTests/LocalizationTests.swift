// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
import LeanDomain

@Suite("Localization", .serialized)
struct LocalizationTests {
    /// Builds a temporary resource folder with `vi.lproj/Localizable.strings`.
    private func makeBundle(_ strings: String) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("l10n-\(UUID().uuidString)")
        let lproj = root.appendingPathComponent("vi.lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try strings.write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        return try #require(Bundle(path: root.path))
    }

    private func withLanguage<T>(_ language: AppLanguage, bundle: Bundle? = nil, _ body: () -> T) -> T {
        if let bundle { L10n.setResourceBundle(bundle) }
        L10n.setLanguage(language)
        defer { L10n.setLanguage(.en); L10n.setResourceBundle(.main) }
        return body()
    }

    @Test func englishReturnsTheSourceTextWithValues() {
        let n = 3
        #expect(withLanguage(.en) { tr("Scanned \(n) items") } == "Scanned 3 items")
        #expect(withLanguage(.en) { tr("Plain text") } == "Plain text")
    }

    @Test func percentSignsSurvive() {
        let level = 80
        #expect(withLanguage(.en) { tr("Charge locked at \(level)%") } == "Charge locked at 80%")
        #expect(withLanguage(.en) { tr("100% sure") } == "100% sure")
    }

    @Test func translatesAndReordersValues() throws {
        let bundle = try makeBundle("""
        "Plain text" = "Văn bản";
        "Copied %@ of %@" = "Đã chép %2$@, tổng %1$@";
        "Charge locked at %@%%" = "Đã khóa sạc ở %1$@%%";
        """)
        #expect(withLanguage(.vi, bundle: bundle) { tr("Plain text") } == "Văn bản")
        let (a, b) = (1, "files")
        #expect(withLanguage(.vi, bundle: bundle) { tr("Copied \(a) of \(b)") } == "Đã chép files, tổng 1")
        let level = 80
        #expect(withLanguage(.vi, bundle: bundle) { tr("Charge locked at \(level)%") } == "Đã khóa sạc ở 80%")
    }

    @Test func missingTranslationFallsBackToEnglish() throws {
        let bundle = try makeBundle(#""Other" = "Khác";"#)
        #expect(withLanguage(.vi, bundle: bundle) { tr("Not translated") } == "Not translated")
    }

    @Test func malformedTranslationNeverCrashes() {
        #expect(L10n.substitute("100%", ["x"]) == "100%")
        #expect(L10n.substitute("%@ and %@", ["a"]) == "a and ")
        #expect(L10n.substitute("%9$@", ["a"]) == "")
        #expect(L10n.substitute("%%", []) == "%")
    }

    @Test func languagesAreDiscoverable() {
        #expect(AppLanguage.allCases.contains(.en))
        #expect(AppLanguage.allCases.contains(.vi))
        #expect(AppLanguage.en.displayName == "English")
        #expect(Set(AppLanguage.allCases.map(\.code)) == ["en", "vi", "ja", "zh-Hans", "ko", "es"])
        #expect(AppLanguage.allCases.allSatisfy { !$0.displayName.isEmpty })
    }
}

@Suite("Language default")
struct LanguageDefaultTests {
    @Test func followsSystemWhenSupported() {
        #expect(AppLanguage.systemDefault(preferred: ["vi-VN", "en-US"]) == .vi)
        #expect(AppLanguage.systemDefault(preferred: ["fr-FR", "vi"]) == .vi)
    }
    @Test func mapsNewLanguagesAndAnyChinese() {
        #expect(AppLanguage.systemDefault(preferred: ["ja-JP"]) == .ja)
        #expect(AppLanguage.systemDefault(preferred: ["ko-KR"]) == .ko)
        #expect(AppLanguage.systemDefault(preferred: ["es-419"]) == .es)
        #expect(AppLanguage.systemDefault(preferred: ["zh-Hans-CN"]) == .zhHans)
        #expect(AppLanguage.systemDefault(preferred: ["zh-Hant-TW"]) == .zhHans)
    }
    @Test func fallsBackToEnglish() {
        #expect(AppLanguage.systemDefault(preferred: ["fr-FR"]) == .en)
        #expect(AppLanguage.systemDefault(preferred: []) == .en)
    }
}
