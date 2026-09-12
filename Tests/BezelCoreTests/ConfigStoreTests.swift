import XCTest
@testable import BezelCore

/// The store that owns the whole configuration and the file behind it.
@MainActor
final class ConfigStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bezel-config-store-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var file: ConfigFile { ConfigFile(url: directory.appendingPathComponent("config.json")) }

    /// A store on this test's own file.
    private func store() -> ConfigStore {
        ConfigStore(file: file)
    }

    // MARK: - First run

    func testAStoreWithNoFileSeedsOneManagedHostAndWritesIt() {
        let store = self.store()

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertTrue(store.hosts[0].managed)
        XCTAssertEqual(store.hosts[0].baseURL, "http://127.0.0.1:3080")
        XCTAssertEqual(store.selectedHostID, store.hosts[0].id)
        XCTAssertNil(store.lastConnectedHostID)
        XCTAssertEqual(store.language, .english)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testSeededHostKeepsItsIdentityAcrossInstances() {
        let first = store()
        let second = store()
        XCTAssertEqual(second.hosts.map(\.id), first.hosts.map(\.id))
    }

    // MARK: - Remembering

    func testEditsAndSelectionSurviveARelaunch() {
        let first = store()
        let added = first.add()
        var edited = added
        edited.name = "实验室"
        edited.baseURL = "http://10.0.0.5:3080"
        edited.token = "tok"
        first.update(edited)

        let second = store()
        XCTAssertEqual(second.hosts.count, 2)
        XCTAssertEqual(second.selectedHost?.name, "实验室")
        XCTAssertEqual(second.selectedHost?.loadURL?.absoluteString, "http://10.0.0.5:3080/?token=tok")
    }

    func testDSHPathSurvivesARelaunch() {
        let first = store()
        var edited = first.hosts[0]
        edited.dshPath = "/opt/homebrew/bin/dsh"
        first.update(edited)

        XCTAssertEqual(store().hosts[0].dshPath, "/opt/homebrew/bin/dsh")
    }

    /// The custom start command is what "manual managed" survives as.
    func testLaunchCommandSurvivesARelaunch() {
        let first = store()
        var edited = first.hosts[0]
        edited.launchCommand = "cd ~/x && dsh web"
        first.update(edited)

        XCTAssertEqual(store().hosts[0].launchCommand, "cd ~/x && dsh web")
    }

    /// A bookmark added by the guide is a bookmark like any other.
    func testAGivenHostCanBeAddedWithoutSelectingIt() {
        let store = self.store()
        let selected = store.selectedHostID
        let added = store.add(DSHHost(name: "实验室", baseURL: "http://10.0.0.5:3080"))

        XCTAssertEqual(store.hosts.map(\.id).last, added.id)
        XCTAssertEqual(store.selectedHostID, selected)
    }

    func testTheLanguageSurvivesARelaunch() {
        let first = store()
        first.setLanguage(.simplifiedChinese)

        XCTAssertEqual(store().language, .simplifiedChinese)
        XCTAssertEqual(Localization(language: store().language).text(.toolbarReload), "重新加载")
    }

    /// What the next launch reconnects to is the Host that was attached, which
    /// is not necessarily the one the picker was left on.
    func testTheLastConnectedHostIsRememberedApartFromTheSelection() {
        let first = store()
        let seeded = first.hosts[0]
        let other = first.add()          // adding also selects
        first.select(id: seeded.id)       // picker moves back…
        first.noteConnected(id: other.id) // …but this is what was attached

        let second = store()
        XCTAssertEqual(second.selectedHostID, seeded.id)
        XCTAssertEqual(second.lastConnectedHostID, other.id)
        XCTAssertEqual(second.host(id: second.lastConnectedHostID)?.id, other.id)
    }

    func testANewBookmarkIsNamedInTheConfiguredLanguage() {
        let store = self.store()
        store.setLanguage(.simplifiedChinese)

        XCTAssertEqual(store.add().name, "新 Host")
    }

    func testRemovingTheSelectedHostClearsItsReferences() {
        let store = self.store()
        let only = store.selectedHostID!
        store.select(id: only)
        store.noteConnected(id: only)

        store.remove(id: only)

        XCTAssertTrue(store.hosts.isEmpty)
        XCTAssertNil(store.selectedHostID)
        XCTAssertNil(store.lastConnectedHostID)
    }

    // MARK: - Notifications setting

    func testNotificationsAreOnByDefault() {
        XCTAssertTrue(store().notificationsEnabled)
    }

    func testTheNotificationsChoiceSurvivesARelaunch() {
        let first = store()
        first.setNotificationsEnabled(false)

        XCTAssertFalse(store().notificationsEnabled)
    }

    /// A file written before the setting existed must load with the setting
    /// at its default, the same leniency every other scalar gets.
    func testAFileFromBeforeTheNotificationsFieldDefaultsToOn() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = #"""
        {"version":1,"language":"en","hosts":[{"id":"3E274921-22D2-45C7-8DCD-DB96A0D80B98","name":"实验室","baseURL":"http://10.0.0.5:3080","token":"","managed":false,"profile":"web","extraArguments":""}]}
        """#
        try Data(text.utf8).write(to: file.url)

        let store = self.store()
        XCTAssertTrue(store.notificationsEnabled)

        // And once rewritten, the field is there to stay.
        store.setNotificationsEnabled(false)
        XCTAssertFalse(self.store().notificationsEnabled)
    }

    // MARK: - First-launch guide

    /// A fresh install is the one case that starts out due a guide.
    func testAStoreWithNoFileOwesTheGuide() {
        let store = self.store()
        XCTAssertFalse(store.onboardingCompleted)
        // …and the fresh file says so, so an abandoned first run shows it
        // again rather than silently graduating.
        XCTAssertFalse(self.store().onboardingCompleted)
    }

    func testCompletingTheGuideSticksAcrossARelaunch() {
        let first = store()
        first.completeOnboarding()

        XCTAssertTrue(first.onboardingCompleted)
        XCTAssertTrue(store().onboardingCompleted)
        // Idempotent, so however many times it is called, it is still one
        // state change written once.
        first.completeOnboarding()
        XCTAssertTrue(first.onboardingCompleted)
    }

    /// A file written before the guide existed belongs to someone who is long
    /// past their first launch; the upgrade must not ambush them with it.
    func testAFileFromBeforeTheGuideCountsAsOnboarded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = #"""
        {"version":1,"language":"en","hosts":[{"id":"3E274921-22D2-45C7-8DCD-DB96A0D80B98","name":"实验室","baseURL":"http://10.0.0.5:3080","token":"","managed":false,"profile":"web","extraArguments":""}]}
        """#
        try Data(text.utf8).write(to: file.url)

        XCTAssertTrue(store().onboardingCompleted)
    }

    /// Deleting the file is the documented reset, and that includes the
    /// guide: it is part of "everything the app remembers".
    func testADeletedFileBringsTheGuideBack() {
        let first = store()
        first.completeOnboarding()
        try? FileManager.default.removeItem(at: file.url)

        XCTAssertFalse(store().onboardingCompleted)
    }

    // MARK: - Reset

    /// Deleting the file is the documented reset: the next store seeds afresh,
    /// in the default language, no matter what the deleted file held.
    func testADeletedFileYieldsAFreshSeed() {
        let first = store()
        first.setLanguage(.simplifiedChinese)
        _ = first.add()
        _ = first.add()

        try? FileManager.default.removeItem(at: file.url)

        let second = store()
        XCTAssertEqual(second.hosts.count, 1)
        XCTAssertEqual(second.hosts[0].name, "Local dsh")
        XCTAssertEqual(second.language, .english)
    }

    // MARK: - Robustness

    /// A file this build cannot parse must be reported, not replaced: it may be
    /// a hand edit that needs a typo fixed, or a newer schema.
    func testAnUnreadableFileIsReportedAndNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("{\"hosts\": not json".utf8)
        try garbage.write(to: file.url)

        let store = self.store()
        XCTAssertTrue(store.dataUnreadable)
        XCTAssertNotNil(store.unreadableReason)
        XCTAssertEqual(store.hosts.count, 1)

        // Nothing the user does through the app may clobber it.
        store.add()
        store.setLanguage(.simplifiedChinese)
        store.remove(id: store.hosts[0].id)

        XCTAssertEqual(try Data(contentsOf: file.url), garbage)
    }

    /// A full disk or a read-only home must be reported rather than silently
    /// losing the change.
    func testAFailedWriteIsReported() throws {
        // A regular file where the config's directory needs to be.
        let blocker = directory.appendingPathComponent("blocker")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: blocker)

        let store = ConfigStore(file: ConfigFile(url: blocker.appendingPathComponent("config.json")))
        store.setLanguage(.simplifiedChinese)

        XCTAssertNotNil(store.writeError)
    }

    /// A file from a newer build is *used* — the user's Hosts are theirs to see
    /// — but never written back, because this build cannot promise to preserve
    /// fields it has no idea about.
    func testAFileFromANewerBuildIsUsedButNeverWritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("""
        {"version":99,"language":"zh-Hans","hosts":[{"name":"future","baseURL":"http://10.0.0.9:3080"}],\
        "futureField":{"a":1}}
        """.utf8)
        try original.write(to: file.url)

        let store = self.store()
        XCTAssertFalse(store.dataUnreadable)
        XCTAssertTrue(store.fileFromNewerBuild)
        XCTAssertEqual(store.fileVersion, 99)
        // Read and used, repairs and all: the bookmark is there and selected.
        XCTAssertEqual(store.hosts.map(\.name), ["future"])
        XCTAssertEqual(store.selectedHostID, store.hosts[0].id)
        XCTAssertEqual(store.language, .simplifiedChinese)

        store.add()
        store.setLanguage(.english)
        store.setNotificationsEnabled(false)

        XCTAssertEqual(try Data(contentsOf: file.url), original)
        XCTAssertNil(store.writeError)
    }

    /// The file's own version is what decides this, not merely "some key I do
    /// not know": a same-version file with an unrecognised key is a file this
    /// build may still own and rewrite, carrying that key through.
    func testASameVersionFileWithUnknownKeysIsStillWritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":1,"hosts":[],"strayKey":"kept"}"#.utf8).write(to: file.url)

        let store = self.store()
        XCTAssertFalse(store.fileFromNewerBuild)
        store.setLanguage(.simplifiedChinese)

        let rewritten = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any]
        )
        XCTAssertEqual(rewritten["language"] as? String, "zh-Hans")
        XCTAssertEqual(rewritten["strayKey"] as? String, "kept")
    }

    func testABookmarkWithoutTheNewerFieldsStillLoads() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = #"""
        {"version":1,"language":"en","hosts":[{"id":"3E274921-22D2-45C7-8DCD-DB96A0D80B98","name":"实验室","baseURL":"http://10.0.0.5:3080","token":"","managed":false,"profile":"web","extraArguments":""}]}
        """#
        try Data(text.utf8).write(to: file.url)

        let store = self.store()
        XCTAssertFalse(store.dataUnreadable)
        XCTAssertEqual(store.hosts.map(\.name), ["实验室"])
        XCTAssertEqual(store.hosts[0].dshPath, "")
        XCTAssertEqual(store.hosts[0].launchCommand, "")
        XCTAssertEqual(store.selectedHostID, store.hosts[0].id)
    }

    /// A reference to a bookmark that is gone is dropped, not left dangling.
    func testDanglingReferencesAreRepairedAndSaved() {
        let missing = UUID()
        try? file.save(AppConfig(
            hosts: [DSHHost(name: "only", baseURL: "http://127.0.0.1:3080")],
            selectedHostID: missing,
            lastConnectedHostID: missing
        ))

        let store = self.store()
        XCTAssertEqual(store.selectedHostID, store.hosts[0].id)
        XCTAssertNil(store.lastConnectedHostID)

        guard case .loaded(let reloaded) = file.load() else {
            return XCTFail("expected a repaired file")
        }
        XCTAssertEqual(reloaded.selectedHostID, store.hosts[0].id)
        XCTAssertNil(reloaded.lastConnectedHostID)
    }
}
