import XCTest
@testable import AriaRuntimeShared

final class AriaCodexProfileTests: XCTestCase {
    func testMergedConfigInstallsAriaProfileAndApprovals() {
        let merged = AriaCodexProfile.mergedConfig(
            existing: """
            model = "gpt-5.4"

            [mcp_servers.aria-runtime]
            command = "/tmp/aria"
            args = ["mcp", "serve"]
            """,
            developerInstructionsFile: "/Users/test/.codex/aria-runtime/developer_instructions.md"
        )

        XCTAssertTrue(merged.contains(#"profile = "aria""#))
        XCTAssertTrue(merged.contains(#"[profiles.aria]"#))
        XCTAssertTrue(merged.contains(#"developer_instructions_file = "/Users/test/.codex/aria-runtime/developer_instructions.md""#))
        XCTAssertTrue(merged.contains(#"disabled_tools = ["web_search", "tool_search"]"#))
        XCTAssertTrue(merged.contains(#"[mcp_servers.aria-runtime.tools.computer_action]"#))
        XCTAssertTrue(merged.contains(#"approval_mode = "approve""#))
    }

    func testMergedConfigReplacesExistingAriaProfileBlock() {
        let merged = AriaCodexProfile.mergedConfig(
            existing: """
            profile = "custom"

            [profiles.aria]
            developer_instructions_file = "/tmp/old.md"
            disabled_tools = ["web_search"]
            """,
            developerInstructionsFile: "/Users/test/.codex/aria-runtime/developer_instructions.md"
        )

        XCTAssertEqual(merged.components(separatedBy: #"[profiles.aria]"#).count - 1, 1)
        XCTAssertTrue(merged.contains(#"profile = "aria""#))
        XCTAssertFalse(merged.contains(#"profile = "custom""#))
        XCTAssertFalse(merged.contains(#"developer_instructions_file = "/tmp/old.md""#))
    }

    func testRemovingProfileDropsDefaultProfileAndAriaSection() {
        let cleaned = AriaCodexProfile.removingProfile(
            from: """
            profile = "aria"

            [profiles.aria]
            developer_instructions_file = "/tmp/aria.md"
            disabled_tools = ["web_search", "tool_search"]

            [mcp_servers.aria-runtime]
            command = "/tmp/aria"
            args = ["mcp", "serve"]
            """
        )

        XCTAssertFalse(cleaned.contains(#"profile = "aria""#))
        XCTAssertFalse(cleaned.contains(#"[profiles.aria]"#))
        XCTAssertTrue(cleaned.contains(#"[mcp_servers.aria-runtime]"#))
    }
}
