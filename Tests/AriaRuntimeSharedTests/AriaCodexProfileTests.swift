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
            modelInstructionsFile: "/Users/test/.codex/aria-runtime/model_instructions.md"
        )

        XCTAssertTrue(merged.contains(#"profile = "aria""#))
        XCTAssertTrue(merged.contains(#"[profiles.aria]"#))
        XCTAssertTrue(merged.contains(#"model_instructions_file = "/Users/test/.codex/aria-runtime/model_instructions.md""#))
        XCTAssertTrue(merged.contains(#"web_search = "disabled""#))
        XCTAssertTrue(merged.contains(#"[mcp_servers.aria-runtime]"#))
        XCTAssertTrue(merged.contains(#"enabled_tools = ["runtime_health", "runtime_permissions", "aria_bootstrap", "system_open_application", "system_open_url", "computer_snapshot", "computer_action"]"#))
        XCTAssertTrue(merged.contains(#"[mcp_servers.aria-runtime.tools.computer_action]"#))
        XCTAssertTrue(merged.contains(#"approval_mode = "approve""#))
    }

    func testMergedConfigReplacesExistingAriaProfileBlock() {
        let merged = AriaCodexProfile.mergedConfig(
            existing: """
            profile = "custom"

            [profiles.aria]
            model_instructions_file = "/tmp/old.md"
            web_search = "live"

            [mcp_servers.aria-runtime]
            enabled_tools = ["read_clipboard"]
            """,
            modelInstructionsFile: "/Users/test/.codex/aria-runtime/model_instructions.md"
        )

        XCTAssertEqual(merged.components(separatedBy: #"[profiles.aria]"#).count - 1, 1)
        XCTAssertTrue(merged.contains(#"profile = "aria""#))
        XCTAssertFalse(merged.contains(#"profile = "custom""#))
        XCTAssertFalse(merged.contains(#"model_instructions_file = "/tmp/old.md""#))
        XCTAssertTrue(merged.contains(#"web_search = "disabled""#))
        XCTAssertTrue(merged.contains(#"enabled_tools = ["runtime_health", "runtime_permissions", "aria_bootstrap", "system_open_application", "system_open_url", "computer_snapshot", "computer_action"]"#))
    }

    func testRemovingProfileDropsDefaultProfileAndAriaSection() {
        let cleaned = AriaCodexProfile.removingProfile(
            from: """
            profile = "aria"

            [profiles.aria]
            model_instructions_file = "/tmp/aria.md"
            web_search = "disabled"

            [mcp_servers.aria-runtime]
            command = "/tmp/aria"
            args = ["mcp", "serve"]
            """
        )

        XCTAssertFalse(cleaned.contains(#"profile = "aria""#))
        XCTAssertFalse(cleaned.contains(#"[profiles.aria]"#))
        XCTAssertTrue(cleaned.contains(#"[mcp_servers.aria-runtime]"#))
    }

    func testModelInstructionsBlockDeeplinkFormFillingAndDefineScrollDirection() {
        let instructions = AriaCodexProfile.modelInstructionsText()

        XCTAssertTrue(instructions.contains("Do not use deeplinks"))
        XCTAssertTrue(instructions.contains("For Gmail/email/message tasks"))
        XCTAssertTrue(instructions.contains("positive delta_y means scroll down"))
        XCTAssertTrue(instructions.contains("After the first computer_action"))
        XCTAssertTrue(instructions.contains("behave like a human operator"))
        XCTAssertTrue(instructions.contains("N concrete things"))
    }
}
