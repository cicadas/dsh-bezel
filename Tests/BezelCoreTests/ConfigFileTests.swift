import XCTest
@testable import BezelCore

/// The file itself: where it lives, what it looks like, and how it fails.
final class ConfigFileTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-config-file-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func file(_ name: String = "config.json") -> ConfigFile {
        ConfigFile(url: directory.appendingPathComponent(name))
    }

    // MARK: - Location

    func testDefaultLocationIsApplicationSupport() {
        let url = ConfigFile.defaultURL(environment: [:], home: "/Users/example")
        XCTAssertEqual(url.path, "/Users/example/Library/Application Support/dsh-bezel/config.json")
    }

    func testTheEnvironmentOverrideWins() {
        let url = ConfigFile.defaultURL(
            environment: [ConfigFile.environmentVariable: "/tmp/portable/config.json"],
            home: "/Users/example"
        )
        XCTAssertEqual(url.path, "/tmp/portable/config.json")
    }

    func testTheEnvironmentOverrideExpandsTilde() {
        let url = ConfigFile.defaultURL(
            environment: [ConfigFile.environmentVariable: "~/portable/config.json"],
            home: "/Users/example"
        )
        XCTAssertEqual(url.path, "/Users/example/portable/config.json")
    }

    func testABlankOverrideIsIgnored() {
        let url = ConfigFile.defaultURL(
            environment: [ConfigFile.environmentVariable: "   "],
            home: "/Users/example"
        )
        XCTAssertEqual(url.path, "/Users/example/Library/Application Support/dsh-bezel/config.json")
    }

    // MARK: - Round trip

    func testSaveThenLoadRoundTripsEverything() throws {
        let host = DSHHost(
            name: "实验室",
            baseURL: "http://10.0.0.5:3080",
            token: "tok",
            managed: false,
            profile: "web",
            extraArguments: "--patch ./x.yml",
            dshPath: "/opt/homebrew/bin/dsh"
        )
        let config = AppConfig(
            language: .simplifiedChinese,
            hosts: [host],
            selectedHostID: host.id,
            lastConnectedHostID: host.id
        )

        let file = file()
        try file.save(config)

        guard case .loaded(let loaded) = file.load() else {
            return XCTFail("expected the saved file to load")
        }
        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.hosts[0].token, "tok")
    }

    func testSaveCreatesItsDirectory() throws {
        let file = file("nested/deeper/config.json")
        try file.save(AppConfig())

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testSavingTwiceReplacesTheFile() throws {
        let file = file()
        let first = DSHHost(name: "first", baseURL: "http://127.0.0.1:3080")
        try file.save(AppConfig(hosts: [first]))
        try file.save(AppConfig(hosts: [DSHHost(name: "second", baseURL: "http://127.0.0.1:3081")]))

        guard case .loaded(let loaded) = file.load() else {
            return XCTFail("expected the overwritten file to load")
        }
        XCTAssertEqual(loaded.hosts.map(\.name), ["second"])
    }

    // MARK: - What a human sees

    func testTheFileIsWrittenToBeReadByAPerson() throws {
        let file = file()
        try file.save(AppConfig(
            language: .simplifiedChinese,
            hosts: [DSHHost(name: "local", baseURL: "http://127.0.0.1:3080")]
        ))

        let text = try XCTUnwrap(String(data: Data(contentsOf: file.url), encoding: .utf8))
        XCTAssertTrue(text.contains("\"language\" : \"zh-Hans\""), text)
        // Sorted keys and unescaped slashes: this file is meant to be diffed.
        XCTAssertFalse(text.contains("\\/"), text)
        XCTAssertTrue(text.contains("\"hosts\""), text)
        XCTAssertTrue(text.contains("http://127.0.0.1:3080"), text)
    }

    func testTheFileIsOwnerOnlyBecauseItCanHoldAToken() throws {
        let file = file()
        try file.save(AppConfig(hosts: [DSHHost(name: "local", baseURL: "http://127.0.0.1:3080", token: "secret")]))

        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    /// Whatever permissions the file started with, a save leaves it
    /// owner-only — and the temporary file the atomic write went through is
    /// gone afterwards.
    func testSavingTightensAnExistingFileToOwnerOnly() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: file.url.path,
            contents: Data("{}".utf8),
            attributes: [.posixPermissions: 0o644]
        )

        try file.save(AppConfig())

        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        let neighbours = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(neighbours.contains { $0.hasSuffix(".tmp") }, "\(neighbours)")
    }

    // MARK: - Failure modes

    func testNoFileIsMissingNotUnreadable() {
        XCTAssertEqual(file().load(), ConfigFile.LoadOutcome.missing)
    }

    func testAnEmptyFileIsUnreadableRatherThanAFreshInstall() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: file.url)

        guard case .unreadable(let reason) = file.load() else {
            return XCTFail("an empty file must not look like a fresh install")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testGarbageIsUnreadableAndTheReasonIsUsable() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: file.url)

        guard case .unreadable(let reason) = file.load() else {
            return XCTFail("expected unreadable")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testOneMalformedBookmarkMakesTheFileUnreadable() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The first entry is fine; losing it silently would be worse than
        // refusing to parse, so the whole file is reported as unreadable.
        let text = #"{"hosts":[{"name":"good","baseURL":"http://127.0.0.1:3080"},"not-an-object"]}"#
        try Data(text.utf8).write(to: file.url)

        guard case .unreadable = file.load() else {
            return XCTFail("expected unreadable")
        }
    }

    /// A scalar this build cannot read falls back to its default; only the
    /// bookmarks are worth refusing to parse over.
    func testAScalarOfTheWrongTypeFallsBackToItsDefault() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = #"{"version":"one","language":5,"selectedHostID":false,"hosts":[]}"#
        try Data(text.utf8).write(to: file.url)

        guard case .loaded(let config) = file.load() else {
            return XCTFail("expected the file to load")
        }
        XCTAssertEqual(config.version, AppConfig.currentVersion)
        XCTAssertEqual(config.language, .english)
        XCTAssertNil(config.selectedHostID)
    }

    func testUnknownKeysAreIgnored() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = #"{"language":"zh-Hans","somethingNewer":42,"hosts":[]}"#
        try Data(text.utf8).write(to: file.url)

        guard case .loaded(let config) = file.load() else {
            return XCTFail("expected the file to load")
        }
        XCTAssertEqual(config.language, .simplifiedChinese)
    }

    /// A file from a newer build is shown as far as this build understands it,
    /// rather than declared corrupt.
    func testAFileFromANewerBuildStillLoads() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = #"{"version":99,"language":"en","hosts":[{"name":"future","baseURL":"http://127.0.0.1:3080"}]}"#
        try Data(text.utf8).write(to: file.url)

        guard case .loaded(let config) = file.load() else {
            return XCTFail("expected the file to load")
        }
        XCTAssertEqual(config.version, 99)
        XCTAssertEqual(config.hosts.map(\.name), ["future"])
        XCTAssertTrue(config.isFromANewerBuild)
    }

    /// Reading tolerantly is only half the promise: a rewrite must not drop the
    /// keys this build has no field for.
    ///
    /// It used to. Unknown keys were ignored on decode and simply absent on
    /// encode, so one ordinary save — a language change is enough — wrote back
    /// a file that still said `"version": 99` with the version-99 part gone.
    func testUnknownFieldsSurviveARewrite() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = """
        {"version":99,"language":"en","hosts":[],\
        "futureScalar":7,"futureFlag":true,"futureNull":null,\
        "futureObject":{"a":1,"b":["x",2.5]},"futureArray":[1,"two"]}
        """
        try Data(text.utf8).write(to: file.url)

        guard case .loaded(var config) = file.load() else {
            return XCTFail("expected the file to load")
        }
        config.language = .simplifiedChinese
        try file.save(config)

        let rewritten = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any]
        )
        XCTAssertEqual(rewritten["language"] as? String, "zh-Hans")
        XCTAssertEqual(rewritten["version"] as? Int, 99)
        XCTAssertEqual(rewritten["futureScalar"] as? Int, 7)
        XCTAssertEqual(rewritten["futureFlag"] as? Bool, true)
        XCTAssertTrue(rewritten["futureNull"] is NSNull)
        XCTAssertEqual(rewritten["futureArray"] as? [AnyHashable], [1, "two"])
        let object = try XCTUnwrap(rewritten["futureObject"] as? [String: Any])
        XCTAssertEqual(object["a"] as? Int, 1)
        XCTAssertEqual(object["b"] as? [AnyHashable], ["x", 2.5])
    }

    /// An integer must not come back as `3080.0`: the file is meant to be read
    /// and diffed, and a rewrite should look like the original.
    func testCarriedIntegersStayIntegers() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"hosts":[],"futurePort":3080}"#.utf8).write(to: file.url)

        guard case .loaded(let config) = file.load() else {
            return XCTFail("expected the file to load")
        }
        try file.save(config)

        let text = try XCTUnwrap(String(data: Data(contentsOf: file.url), encoding: .utf8))
        XCTAssertTrue(text.contains("\"futurePort\" : 3080"), text)
    }

    /// A carried-through key that collides with one of this build's own fields
    /// must not shadow it — the round trip has to stay stable.
    func testThisBuildsOwnFieldsWinACollision() throws {
        let file = file()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"language":"zh-Hans","hosts":[]}"#.utf8).write(to: file.url)

        guard case .loaded(var config) = file.load() else {
            return XCTFail("expected the file to load")
        }
        XCTAssertTrue(config.unknownFields.isEmpty)
        // A hand-forged collision: the encoder must prefer the real field.
        config.unknownFields["language"] = .string("de")
        try file.save(config)

        guard case .loaded(let reloaded) = file.load() else {
            return XCTFail("expected the rewritten file to load")
        }
        XCTAssertEqual(reloaded.language, .simplifiedChinese)
    }

    func testDescribeReportsWhatIsThere() throws {
        let missing = file()
        XCTAssertTrue(missing.describe().contains("no config file at"), missing.describe())

        try missing.save(AppConfig(language: .simplifiedChinese, hosts: []))
        let loaded = missing.describe()
        XCTAssertTrue(loaded.contains("\"language\" : \"zh-Hans\""), loaded)

        try Data("broken".utf8).write(to: missing.url)
        XCTAssertTrue(missing.describe().contains("cannot be read"), missing.describe())
    }
}
