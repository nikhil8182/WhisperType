import XCTest
import Cocoa
@testable import WhisperType

final class DictationRegressionTests: XCTestCase {
    func testRightOptionReleaseWhileLeftOptionRemainsHeld() {
        let leftOnly = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)
        XCTAssertFalse(HotkeyManager.isHotkeyPressed(keyCode: 61, flags: leftOnly))
        XCTAssertTrue(HotkeyManager.isHotkeyPressed(keyCode: 58, flags: leftOnly))
        let both = NSEvent.ModifierFlags(rawValue: leftOnly.rawValue | 0x40)
        XCTAssertTrue(HotkeyManager.isHotkeyPressed(keyCode: 61, flags: both))
    }

    func testClipboardRestoresAllTypesAndItems() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .png)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        board.writeObjects([item, second])
        let original = TextPaster.snapshot(board)
        board.clearContents()
        board.setString("dictation", forType: .string)
        XCTAssertTrue(TextPaster.restore(original, to: board, ifUnchanged: board.changeCount))
        XCTAssertEqual(TextPaster.snapshot(board), original)
    }

    func testClipboardDoesNotOverwriteNewCopy() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let original = TextPaster.snapshot(board)
        board.clearContents()
        board.setString("dictation", forType: .string)
        let count = board.changeCount
        board.clearContents()
        board.setString("user copied this", forType: .string)
        XCTAssertFalse(TextPaster.restore(original, to: board, ifUnchanged: count))
        XCTAssertEqual(board.string(forType: .string), "user copied this")
    }

    func testClipboardRestoresInitiallyEmptyClipboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let original = TextPaster.snapshot(board)
        board.setString("dictation", forType: .string)
        XCTAssertTrue(TextPaster.restore(original, to: board, ifUnchanged: board.changeCount))
        XCTAssertNil(board.string(forType: .string))
    }

    func testCLIFallbackOmitsAutoLanguageAndKeepsExplicitLanguage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("whisper-stub")
        // The actual Process path runs, but outputs its arguments instead of loading a model.
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let manager = WhisperManager(whisperPath: executable.path)
        for language in ["auto", "", "ta"] {
            let done = expectation(description: "CLI \(language)")
            manager.transcribe(audioURL: directory.appendingPathComponent("sample.wav"), model: "base", language: language) { result in
                switch result {
                case .success(let output):
                    let args = output.split(separator: "\n").map(String.init)
                    if language == "ta" {
                        XCTAssertTrue(output.contains("--language\nta"))
                    } else {
                        XCTAssertFalse(args.contains("--language"))
                    }
                case .failure(let error): XCTFail("\(error)")
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
    }

    private func polish(status: Int, body: String, expected: String) {
        StubProtocol.status = status
        StubProtocol.body = body.data(using: .utf8)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = EngineClient(session: session)
        let done = expectation(description: "polish completion")
        client.polish(text: "discard this scratch that", app: .init(bundle: "", name: "", title: ""), styleOverride: "prompt") { result in
            XCTAssertEqual(result.text, expected)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testSuccessfulScratchThatKeepsEmptyResult() {
        polish(status: 200, body: #"{"text":"","style":"prompt","llm":false}"#, expected: "")
    }

    func testSuccessfulNewParagraphKeepsWhitespace() {
        polish(status: 200, body: #"{"text":"\n\n","style":"prompt","llm":false}"#, expected: "\n\n")
    }

    func testFailedPolishUsesOriginalText() {
        polish(status: 500, body: #"{"text":"bad server output"}"#, expected: "discard this scratch that")
    }
}

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
