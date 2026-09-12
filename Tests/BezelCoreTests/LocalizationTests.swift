import XCTest
@testable import BezelCore

@MainActor
final class LocalizationTests: XCTestCase {
    func testEnglishIsTheDefault() {
        XCTAssertEqual(AppLanguage.fallback, .english)
        XCTAssertEqual(Localization().language, .english)
        XCTAssertEqual(Localization().text(.toolbarReload), "Reload")
    }

    func testEachLanguageNamesItself() {
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.traditionalChinese.displayName, "繁體中文")
        XCTAssertEqual(AppLanguage.japanese.displayName, "日本語")
        XCTAssertEqual(AppLanguage.french.displayName, "Français")
        XCTAssertEqual(AppLanguage.german.displayName, "Deutsch")
        XCTAssertEqual(AppLanguage.spanish.displayName, "Español")
    }

    /// The picker shows one entry per language, and no two of them read alike.
    func testLanguageNamesAreDistinct() {
        let names = AppLanguage.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "two languages name themselves the same way")
    }

    /// A raw value is written to the config file, so it is part of the format:
    /// renaming one would silently reset a user's choice on the next launch.
    func testRawValuesAreTheStableCodes() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "zh-Hans", "zh-Hant", "ja", "fr", "de", "es"])
    }

    func testNoMessageIsBlank() {
        for message in Message.allCases {
            for language in AppLanguage.allCases {
                let text = Localization(language: language).text(message)
                XCTAssertFalse(text.isEmpty, "\(message) is empty in \(language.rawValue)")
            }
        }
    }

    /// Catches the usual way a translation rots: the English string pasted
    /// into another table and never revisited.
    func testEveryTranslationIsActuallyTranslated() {
        for language in AppLanguage.allCases where language != .english {
            for message in Message.allCases where !Self.readsTheSameAsEnglish(message, in: language) {
                let english = Localization(language: .english).text(message)
                let translated = Localization(language: language).text(message)
                XCTAssertNotEqual(english, translated, "\(message) was not translated into \(language.rawValue)")
            }
        }
    }

    /// A translation that drops `{1}` would silently lose the value it is
    /// about, which is exactly the kind of bug nobody notices until a user
    /// reports a message with a missing port number.
    func testTranslationsUseTheSamePlaceholders() {
        for message in Message.allCases {
            let english = placeholders(in: Localization(language: .english).text(message))
            for language in AppLanguage.allCases where language != .english {
                let translated = placeholders(in: Localization(language: language).text(message))
                XCTAssertEqual(
                    english,
                    translated,
                    "\(message) has mismatched placeholders in \(language.rawValue)"
                )
            }
        }
    }

    func testPlaceholdersAreFilledByPosition() {
        let english = Localization(language: .english)
        let chinese = Localization(language: .simplifiedChinese)

        XCTAssertEqual(english.text(.invalidAddress, "http://x"), "Invalid Host address: http://x")
        XCTAssertEqual(chinese.text(.invalidAddress, "http://x"), "无效的 Host 地址：http://x")
        XCTAssertEqual(chinese.text(.diagnosticChosen, "/opt/bin/dsh", "登录 shell"), "dsh: /opt/bin/dsh（来源：登录 shell）")
        XCTAssertEqual(chinese.text(.failureNoDSH, "3"), "找不到可用的 dsh（已尝试 3 个位置，详见下方输出）")
    }

    func testArgumentsAreNotReusedAcrossCalls() {
        let localization = Localization(language: .english)
        _ = localization.text(.failureTimedOut, "30")
        XCTAssertEqual(
            localization.text(.failureTimedOut, "5"),
            "dsh did not start within 5 seconds"
        )
    }

    func testMessagesWithNoPlaceholderIgnoreArguments() {
        XCTAssertEqual(Localization().text(.toolbarReload, "unused"), "Reload")
    }

    // MARK: - Wording that depends on the language

    func testUntitledHostFollowsTheLanguage() {
        let host = DSHHost()
        XCTAssertEqual(host.displayName(in: Localization(language: .english)), "Untitled Host")
        XCTAssertEqual(host.displayName(in: Localization(language: .simplifiedChinese)), "未命名 Host")
    }

    /// A name the user typed is their data: it must not be translated.
    func testAUserGivenNameIsUsedVerbatimInEveryLanguage() {
        let host = DSHHost(name: "实验室", baseURL: "http://10.0.0.5:3080")
        for language in AppLanguage.allCases {
            XCTAssertEqual(host.displayName(in: Localization(language: language)), "实验室")
        }
    }

    /// Diagnostics are rendered from structured data, so the same report can
    /// be produced in any language.
    func testDiscoveryDiagnosticsFollowTheLanguage() {
        let report = DSHDiscovery.Report(
            chosen: nil,
            environment: ["PATH": "/usr/bin"],
            attempts: [
                DSHDiscovery.Attempt(
                    candidate: DSHCandidate(executable: "/opt/homebrew/bin/dsh", origin: .wellKnown),
                    reason: .didNotRun
                ),
                DSHDiscovery.Attempt(
                    candidate: DSHCandidate(executable: "/usr/local/bin/dsh", origin: .wellKnown),
                    reason: .skipped
                ),
            ]
        )

        let english = report.diagnosticLines(Localization(language: .english))
        XCTAssertEqual(english.first, "No usable dsh found; every location below was tried")
        XCTAssertTrue(english.contains("Child PATH:"))
        XCTAssertTrue(english.contains { $0.contains("common install locations") })
        XCTAssertTrue(english.contains { $0.contains("selected") == false && $0.contains("✗") })
        XCTAssertTrue(english.contains { $0.contains("not tried") })

        let chinese = report.diagnosticLines(Localization(language: .simplifiedChinese))
        XCTAssertEqual(chinese.first, "找不到可用的 dsh：以下位置都试过了")
        XCTAssertTrue(chinese.contains("子进程 PATH："))
        XCTAssertTrue(chinese.contains { $0.contains("常见安装位置") })
    }

    func testChosenExecutableDiagnosticNamesItsSource() {
        let report = DSHDiscovery.Report(
            chosen: DSHCandidate(executable: "/Users/me/.local/bin/dsh", origin: .loginShell),
            environment: [:],
            attempts: [DSHDiscovery.Attempt(
                candidate: DSHCandidate(executable: "/Users/me/.local/bin/dsh", origin: .loginShell),
                reason: .selected
            )]
        )

        XCTAssertEqual(
            report.diagnosticLines(Localization(language: .english)).first,
            "dsh: /Users/me/.local/bin/dsh (source: login shell)"
        )
        XCTAssertEqual(
            report.diagnosticLines(Localization(language: .simplifiedChinese)).first,
            "dsh: /Users/me/.local/bin/dsh（来源：登录 shell）"
        )
    }

    // MARK: - Helpers

    /// A few strings are identifiers or loanwords that legitimately read the
    /// same as the English one, so an equal string there is not evidence of a
    /// missed translation.
    private static func readsTheSameAsEnglish(_ message: Message, in language: AppLanguage) -> Bool {
        // An environment variable's name is spelled the same everywhere.
        if message == .originEnvironmentOverride { return true }
        return sharedWithEnglish[language]?.contains(message) ?? false
    }

    private static let sharedWithEnglish: [AppLanguage: Set<Message>] = [
        .french: [.settingsTabHosts, .settingsNotifications],
        .german: [.settingsTabHosts, .settingsFieldName],
        .spanish: [.settingsTabHosts, .settingsTabGeneral, .onboardingManagedManual],
    ]

    private func placeholders(in template: String) -> Set<Int> {
        Set((1...4).filter { template.contains("{\($0)}") })
    }
}
