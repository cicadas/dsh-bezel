import XCTest
@testable import BezelCore

final class DSHHostTests: XCTestCase {
    func testOriginDropsPathQueryAndTrailingSlash() {
        let host = DSHHost(baseURL: "http://127.0.0.1:3080/?token=stale#frag")
        XCTAssertEqual(host.origin?.absoluteString, "http://127.0.0.1:3080")
        XCTAssertTrue(host.isValid)
    }

    func testOriginKeepsExplicitPortAndScheme() {
        XCTAssertEqual(
            DSHHost(baseURL: "https://dsh.internal:8443").origin?.absoluteString,
            "https://dsh.internal:8443"
        )
    }

    func testRejectsNonHTTPAndHostlessAddresses() {
        XCTAssertFalse(DSHHost(baseURL: "file:///tmp/index.html").isValid)
        XCTAssertFalse(DSHHost(baseURL: "127.0.0.1:3080").isValid)
        XCTAssertFalse(DSHHost(baseURL: "   ").isValid)
        XCTAssertNil(DSHHost(baseURL: "not a url at all").loadURL)
    }

    func testLoadURLCarriesTokenOnTheRootQuery() {
        let host = DSHHost(baseURL: "http://127.0.0.1:3080", token: "abc123")
        XCTAssertEqual(host.loadURL?.absoluteString, "http://127.0.0.1:3080/?token=abc123")
    }

    func testLoadURLWithoutTokenIsTheBareOrigin() {
        let host = DSHHost(baseURL: "http://127.0.0.1:3080/")
        XCTAssertEqual(host.loadURL?.absoluteString, "http://127.0.0.1:3080")
    }

    func testArgumentListSplitsOnWhitespace() {
        let host = DSHHost(extraArguments: "  --trusted-host dsh.internal\n--patch ./extra.yml ")
        XCTAssertEqual(host.argumentList, ["--trusted-host", "dsh.internal", "--patch", "./extra.yml"])
    }

    func testDisplayNameFallsBackToOrigin() {
        XCTAssertEqual(DSHHost(name: "   ", baseURL: "http://127.0.0.1:3080").displayName(), "http://127.0.0.1:3080")
        XCTAssertEqual(DSHHost(name: "实验室", baseURL: "http://10.0.0.5:3080").displayName(), "实验室")
    }

    // MARK: - Bookmark decoding

    /// A bookmark written before `dshPath` existed has to keep working. The
    /// synthesized decoder fails the whole array over one missing key, and the
    /// store used to answer that failure by overwriting the user's file.
    func testDecodesBookmarksSavedBeforeDSHPathExisted() throws {
        let legacy = """
        [{"id":"3E274921-22D2-45C7-8DCD-DB96A0D80B98","name":"实验室",
          "baseURL":"http://10.0.0.5:3080","token":"tok","managed":true,
          "profile":"web","extraArguments":"--trusted-host dsh.internal"}]
        """
        let hosts = try JSONDecoder().decode([DSHHost].self, from: Data(legacy.utf8))
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].name, "实验室")
        XCTAssertEqual(hosts[0].extraArguments, "--trusted-host dsh.internal")
        XCTAssertEqual(hosts[0].dshPath, "")
    }

    func testDecodingUnknownShapesFallsBackToDefaults() throws {
        let hosts = try JSONDecoder().decode([DSHHost].self, from: Data("[{}]".utf8))
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].profile, "web")
        XCTAssertFalse(hosts[0].managed)
        XCTAssertFalse(hosts[0].isValid)
    }

    func testRoundTripKeepsDSHPath() throws {
        let host = DSHHost(
            name: "n", baseURL: "http://127.0.0.1:3080", managed: true, dshPath: "/opt/bin/dsh"
        )
        XCTAssertEqual(try JSONDecoder().decode(DSHHost.self, from: JSONEncoder().encode(host)), host)
    }
}
