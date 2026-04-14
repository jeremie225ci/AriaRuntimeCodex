import Foundation

public enum AriaControlPlane {
    public static let canonicalVisualTools = [
        "aria_bootstrap",
        "computer_snapshot",
        "computer_action",
    ]

    public static let visualLoopRules = [
        "Call aria_bootstrap exactly once at the start of every visual or UI task.",
        "Use system_open_application or system_open_url only to enter the target app or site before the visual loop.",
        "Capture the screen with computer_snapshot before the first UI action.",
        "Execute exactly one UI action per computer_action call.",
        "Inspect the returned screenshot after every action before choosing the next action.",
        "Treat scroll and drag as successful only when the returned screenshot confirms a visual change.",
        "Verify completion visually before claiming success.",
    ]

    public static let forbiddenDefaults = [
        "Do not use DOM inspection, browser JavaScript, or AppleScript DOM access for visual tasks.",
        "Do not chain multiple UI actions into one call.",
        "Do not guess stale coordinates without a fresh screenshot.",
        "Do not claim a button was clicked or a form was submitted without post-action confirmation.",
    ]

    public static let sensitiveActionRules = [
        "Require explicit user confirmation before send, submit, delete, publish, purchase, or irreversible actions.",
        "If the user asked only to draft or write, stop before the irreversible confirmation step.",
        "Prefer deterministic keyboard shortcuts only when they are standard and clearly scoped to the focused app.",
    ]

    public static let allowedComputerActionTypes = [
        "click",
        "double_click",
        "scroll",
        "type",
        "key_press",
        "wait",
        "move",
        "drag",
    ]

    public static let initializeInstructions = """
    Aria is the control layer for Codex. For any visual task, follow the Aria loop instead of improvising:
    1. Call aria_bootstrap once.
    2. Enter the app or URL if needed.
    3. Call computer_snapshot.
    4. Choose exactly one computer_action.
    5. Inspect the returned screenshot before the next action.
    6. Require explicit user confirmation before send, submit, delete, purchase, publish, or irreversible actions.

    For visual tasks, do not use DOM inspection, Safari JavaScript from Apple Events, or AppleScript UI scraping as the primary strategy. Aria's canonical visual tools are aria_bootstrap, computer_snapshot, and computer_action.
    Specialized desktop helpers may be used when they are more deterministic than raw UI clicks: desktop_list_windows, desktop_focus_application, desktop_focus_window, read_clipboard, read_clipboard_image, copy_to_clipboard, and reveal_path.
    """

    public static func bootstrapPayload(version: String, permissions: [String: JSONValue], availableTools: [String]) -> JSONValue {
        .object([
            "mode": .string("codex_controlled_local_runtime"),
            "server": .string("aria-runtime"),
            "version": .string(version),
            "instructions": .string(initializeInstructions),
            "canonical_visual_tools": .array(canonicalVisualTools.map(JSONValue.string)),
            "available_tools": .array(availableTools.map(JSONValue.string)),
            "allowed_computer_action_types": .array(allowedComputerActionTypes.map(JSONValue.string)),
            "visual_loop_rules": .array(visualLoopRules.map(JSONValue.string)),
            "forbidden_defaults": .array(forbiddenDefaults.map(JSONValue.string)),
            "sensitive_action_rules": .array(sensitiveActionRules.map(JSONValue.string)),
            "permissions": .object(permissions),
            "next_step": .string("Open the target app/site if needed, then call computer_snapshot."),
        ])
    }

    public static func policyResourceText() -> String {
        """
        Aria Computer Use Policy

        Aria is not a second brain. Codex is the only decision engine, but it must operate inside Aria's control loop.

        Mandatory rules:
        - Call aria_bootstrap once at the beginning of each visual task.
        - Use computer_snapshot before the first UI action.
        - Use exactly one computer_action per cycle.
        - Inspect the returned screenshot before deciding again.
        - Verify the outcome visually before declaring completion.

        Forbidden defaults:
        - DOM inspection for visually anchored tasks
        - Safari JavaScript automation as a substitute for visual verification
        - multiple UI actions in one tool call
        - stale coordinate guessing without a fresh screenshot

        Sensitive actions:
        - send
        - submit
        - delete
        - purchase
        - publish

        These require explicit user confirmation.

        Specialized helpers:
        - desktop_list_windows for window discovery
        - desktop_focus_application before a fresh snapshot
        - desktop_focus_window when a specific title or app window matters
        - read_clipboard, read_clipboard_image, and copy_to_clipboard for deterministic clipboard work
        - reveal_path to open Finder to a known file or directory
        """
    }

    public static func workflowResourceText() -> String {
        """
        Aria Visual Workflow

        1. aria_bootstrap
        2. system_open_application or system_open_url if entry is needed
        3. computer_snapshot
        4. computer_action with exactly one action
        5. inspect returned screenshot
        6. repeat until visually verified

        Preferred action grammar:
        - click x/y
        - double_click x/y
        - scroll delta_y
        - type text
        - key_press keys[]
        - wait seconds
        - move x/y
        - drag path[]

        Specialized helpers:
        - desktop_list_windows
        - desktop_focus_application
        - desktop_focus_window
        - read_clipboard
        - read_clipboard_image
        - copy_to_clipboard
        - reveal_path
        """
    }

    public static func installResourceText() -> String {
        """
        Aria Install Surface

        End users should receive packaged binaries only:
        - Aria Runtime.app
        - aria CLI
        - aria-runtime-daemon
        - local MCP configuration

        End users must not need the source repository to use Aria.
        The product should be installable with at most a few commands, then immediately usable from Codex.
        """
    }

    public static func promptText(task: String?) -> String {
        let normalizedTask = task?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let taskLine = normalizedTask.isEmpty ? "" : "\nCurrent user goal: \(normalizedTask)\n"
        return """
        You are operating through Aria Runtime on macOS.\(taskLine)

        Follow the Aria control loop:
        - Call aria_bootstrap first.
        - For visual tasks, do not use DOM inspection or browser JavaScript as the main strategy.
        - Use computer_snapshot to observe the UI.
        - Use computer_action for exactly one UI action at a time.
        - After every action, inspect the returned screenshot before deciding again.
        - Stop before irreversible actions unless the user explicitly asked for that exact action.
        """
    }

    public static func setupTestPrompt() -> String {
        """
        Use aria-runtime for this visual task. Call aria_bootstrap exactly once, then if needed open TextEdit, call computer_snapshot, and use computer_action one step at a time to create a new document and type: Aria Runtime Codex setup test.
        """
    }
}
