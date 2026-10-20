import XCTest
@testable import DeveloppeurKit

final class ClaudeRegistrationTests: XCTestCase {
    func testRegisterKeepsOtherServersAndUnregisterRemovesOnlyOurs() throws {
        let folder = TestSupport.temporaryDirectory()
        let desktop = ClaudeRegistration.Target(label: "Desktop", url: folder.appendingPathComponent("claude_desktop_config.json"))
        let code = ClaudeRegistration.Target(label: "Code", url: folder.appendingPathComponent("sous-dossier/.claude.json"))
        try #"{"mcpServers":{"apple-mail":{"command":"/x/mcp-apple-mail","args":[]}},"autre":1}"#
            .write(to: desktop.url, atomically: true, encoding: .utf8)

        try ClaudeRegistration.register(executable: "/y/mcp-developpeur", targets: [desktop, code])
        XCTAssertEqual(ClaudeRegistration.registeredCommand(in: desktop), "/y/mcp-developpeur")
        XCTAssertEqual(ClaudeRegistration.registeredCommand(in: code), "/y/mcp-developpeur")
        let saved = try JSONCoding.parse(Data(contentsOf: desktop.url))
        XCTAssertEqual(saved["mcpServers"]?["apple-mail"]?["command"]?.string, "/x/mcp-apple-mail")
        XCTAssertEqual(saved["autre"]?.int, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.url.path + ".avant-mcp-developpeur"))

        try ClaudeRegistration.unregister(targets: [desktop, code])
        XCTAssertNil(ClaudeRegistration.registeredCommand(in: desktop))
        let after = try JSONCoding.parse(Data(contentsOf: desktop.url))
        XCTAssertEqual(after["mcpServers"]?["apple-mail"]?["command"]?.string, "/x/mcp-apple-mail")
    }

    func testRegisterRemovesTheReplacedMCPLightroomOnly() throws {
        let folder = TestSupport.temporaryDirectory()
        let desktop = ClaudeRegistration.Target(label: "Desktop", url: folder.appendingPathComponent("claude_desktop_config.json"))
        let code = ClaudeRegistration.Target(label: "Code", url: folder.appendingPathComponent(".claude.json"))
        // Claude Desktop ouvert pendant l'installation : l'ancienne clé revenue (constaté).
        try #"{"mcpServers":{"apple-mail":{"command":"/x/mcp-apple-mail"},"lightroom":{"command":"/Users/d/Library/Application Support/MCP Lightroom/mcp-lightroom","args":[]}}}"#
            .write(to: desktop.url, atomically: true, encoding: .utf8)
        // Une clé « lightroom » qui lance autre chose n'est pas la nôtre.
        try #"{"mcpServers":{"lightroom":{"command":"/autre/serveur-lightroom"}}}"#
            .write(to: code.url, atomically: true, encoding: .utf8)
        XCTAssertTrue(ClaudeRegistration.ancienInscrit(in: desktop))
        XCTAssertFalse(ClaudeRegistration.ancienInscrit(in: code))

        let report = try ClaudeRegistration.register(executable: "/y/mcp-developpeur", targets: [desktop, code])
        XCTAssertTrue(report.contains { $0.hasPrefix("Desktop : ancien connecteur « lightroom »") }, report.joined(separator: "\n"))
        XCTAssertFalse(report.contains { $0.hasPrefix("Code : ancien") })
        XCTAssertFalse(ClaudeRegistration.ancienInscrit(in: desktop))
        let saved = try JSONCoding.parse(Data(contentsOf: desktop.url))
        XCTAssertNil(saved["mcpServers"]?["lightroom"])
        XCTAssertEqual(saved["mcpServers"]?["apple-mail"]?["command"]?.string, "/x/mcp-apple-mail")
        XCTAssertEqual(ClaudeRegistration.registeredCommand(in: desktop), "/y/mcp-developpeur")
        let autre = try JSONCoding.parse(Data(contentsOf: code.url))
        XCTAssertEqual(autre["mcpServers"]?["lightroom"]?["command"]?.string, "/autre/serveur-lightroom")
    }

    func testInvalidFileIsLeftAlone() throws {
        let folder = TestSupport.temporaryDirectory()
        let target = ClaudeRegistration.Target(label: "Desktop", url: folder.appendingPathComponent("config.json"))
        try "[1, 2]".write(to: target.url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ClaudeRegistration.register(executable: "/y", targets: [target]))
        XCTAssertEqual(try String(contentsOf: target.url, encoding: .utf8), "[1, 2]")
    }
}
