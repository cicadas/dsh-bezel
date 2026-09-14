import XCTest
@testable import BezelCore

/// The wire is the part that drifts, so the wire is what these tests pin:
/// frame shapes, payload names, and tolerant decoding are all verified against
/// recorded shapes from a real Host.
final class HostFeedWireTests: XCTestCase {
    func testOpenFrameCarriesTheEventStreamEndpoint() throws {
        let frame = HostFeedWire.openFrame(streamId: "s1")
        let json = try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: Data(frame.utf8)))
        guard case .object(let fields) = json else { return XCTFail("not an object") }
        XCTAssertEqual(fields["type"]?.string, "open")
        XCTAssertEqual(fields["streamId"]?.string, "s1")
        XCTAssertEqual(fields["endpoint"]?.string, "$events")
        XCTAssertEqual(fields["payload"]?.object?["args"], .object([:]))
    }

    func testListRequestBodyNamesMethodAndRequestField() throws {
        let body = HostFeedWire.listRequestBody(rpcId: "r1")
        let json = try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)))
        guard case .object(let fields) = json else { return XCTFail("not an object") }
        XCTAssertEqual(fields["type"]?.string, "client-request")
        XCTAssertEqual(fields["rpcId"]?.string, "r1")
        XCTAssertEqual(fields["method"]?.string, "session/list")
        XCTAssertEqual(fields["payload"]?.object?["args"]?.object?["_request"], .object([:]))
    }

    func testParsesStatusEmitFromItemWrapper() {
        let frame = #"{"type":"item","streamId":"s","value":{"type":"emit","event":"api-session/status","args":["session-1",false]}}"#
        XCTAssertEqual(
            HostFeedWire.parseFrame(frame),
            .runningChanged(id: "session-1", running: false)
        )
    }

    func testParsesUnwrappedEmitToo() {
        let frame = #"{"type":"emit","event":"api-session/status","args":["session-1",true]}"#
        XCTAssertEqual(
            HostFeedWire.parseFrame(frame),
            .runningChanged(id: "session-1", running: true)
        )
    }

    func testIgnoresOtherEmittedEvents() {
        let frame = #"{"type":"item","value":{"type":"emit","event":"settings/document-updated","args":[]}}"#
        XCTAssertNil(HostFeedWire.parseFrame(frame))
    }

    func testIgnoresReadyFrame() {
        let frame = #"{"type":"item","streamId":"s","value":{"type":"ready","clientId":"c","host":{}}}"#
        XCTAssertNil(HostFeedWire.parseFrame(frame))
    }

    func testParsesApprovalSummons() {
        let frame = #"{"type":"item","value":{"type":"waterfall","event":"approval/request","eventId":"e1","agentId":"session-1","request":{"tool":"bash"}}}"#
        XCTAssertEqual(
            HostFeedWire.parseFrame(frame),
            .summons(sessionId: "session-1", kind: .approval, eventId: "e1")
        )
    }

    func testParsesQuestionSummons() {
        let frame = #"{"type":"item","value":{"type":"waterfall","event":"user-questions/request","eventId":"e2","agentId":"session-2","request":{"questions":[{"prompt":"which?"}]}}}"#
        XCTAssertEqual(
            HostFeedWire.parseFrame(frame),
            .summons(sessionId: "session-2", kind: .question, eventId: "e2")
        )
    }

    func testClassifiesPlanReviewInsideQuestionPayload() {
        let frame = #"{"type":"item","value":{"type":"waterfall","event":"user-questions/request","eventId":"e3","agentId":"session-3","request":{"questions":[{"intent":{"kind":"plan-review"}}]}}}"#
        XCTAssertEqual(
            HostFeedWire.parseFrame(frame),
            .summons(sessionId: "session-3", kind: .planReview, eventId: "e3")
        )
    }

    func testPlanReviewMarkerIsFoundWhereverItHides() {
        XCTAssertTrue(HostFeedWire.marksPlanReview(.object(["intent": .object(["kind": .string("plan-review")])])))
        XCTAssertTrue(HostFeedWire.marksPlanReview(.object(["kind": .string("plan-review")])))
        XCTAssertTrue(HostFeedWire.marksPlanReview(.array([.object(["a": .object(["b": .array([.string("plan-review")])])])])))
        XCTAssertFalse(HostFeedWire.marksPlanReview(.object(["intent": .object(["kind": .string("question")])])))
        XCTAssertFalse(HostFeedWire.marksPlanReview(.null))
    }

    func testParsesSummonsCancellation() {
        let frame = #"{"type":"item","streamId":"s","value":{"type":"cancel","eventId":"e1"}}"#
        XCTAssertEqual(HostFeedWire.parseFrame(frame), .summonsEnded(eventId: "e1"))
    }

    func testGarbageIsNilNeverFatal() {
        XCTAssertNil(HostFeedWire.parseFrame("not json at all"))
        XCTAssertNil(HostFeedWire.parseFrame(#"{"type":"item"}"#))
        XCTAssertNil(HostFeedWire.parseFrame(#"[]"#))
    }

    func testDecodesSessionListItems() {
        let envelope = #"{"type":"server-response","rpcId":"r","result":{"ok":true,"value":{"items":[{"sessionId":"session-a","updatedAt":1789369293731,"running":true,"blank":false,"cwd":"/tmp","projections":{"asOfSeq":2,"values":{"title":"My task","goal":null}}},{"sessionId":"session-b","title":"Direct title","running":false}]}}}"#
        XCTAssertEqual(
            HostFeedWire.sessions(from: Data(envelope.utf8)),
            [
                HostSession(id: "session-a", title: "My task", running: true),
                HostSession(id: "session-b", title: "Direct title", running: false),
            ]
        )
    }

    func testDecodingDefaultsWrongTypesAndDropsIdlessRows() {
        // A row without a session id cannot be addressed again, so it is
        // dropped whole; a row with one survives, wrong-typed fields falling
        // back to their defaults — the same tolerance the config file gets.
        let envelope = #"{"type":"server-response","rpcId":"r","result":{"ok":true,"value":{"items":[{"running":true},{"sessionId":"session-c","running":"yes"},{"sessionId":"session-d"}]}}}"#
        XCTAssertEqual(
            HostFeedWire.sessions(from: Data(envelope.utf8)),
            [
                HostSession(id: "session-c", title: nil, running: false),
                HostSession(id: "session-d", title: nil, running: false),
            ]
        )
    }

    func testRefusedResultIsNil() {
        let envelope = #"{"type":"server-response","rpcId":"r","result":{"ok":false,"error":{"code":"gateway/x","message":"no","details":{}}}}"#
        XCTAssertNil(HostFeedWire.sessions(from: Data(envelope.utf8)))
    }

    func testCookieHeaderMatchesAuthority() {
        let cookie = HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: "dsh-auth-hash",
            .value: "v1.sig",
        ])!
        XCTAssertEqual(
            HostFeed.cookieHeader(for: URL(string: "http://127.0.0.1:60177")!, cookies: [cookie]),
            "dsh-auth-hash=v1.sig"
        )
        XCTAssertNil(HostFeed.cookieHeader(for: URL(string: "http://other.example:1")!, cookies: [cookie]))
    }
}
