import Foundation

public enum AriaControlPlane {
    public static let canonicalVisualTools = [
        "aria_bootstrap",
        "system_open_application",
        "system_open_url",
        "computer_snapshot",
        "computer_action",
    ]

    public static let visualLoopRules = [
        "Call aria_bootstrap exactly once at the start of every visual or UI task.",
        "Use system_open_application or system_open_url only to enter the target app or site before the visual loop.",
        "Once the visual loop has started, do not switch to clipboard helpers, window-inspection helpers, DOM helpers, or out-of-band research as a substitute for computer use.",
        "For browser navigation or search where the query or destination is already known, prefer system_open_url over typing into the address bar.",
        "Capture the screen with computer_snapshot before the first UI action.",
        "Execute exactly one UI action per computer_action call.",
        "Inspect the returned screenshot after every action before choosing the next action.",
        "Treat scroll and drag as successful only when the returned screenshot confirms a visual change.",
        "Verify completion visually before claiming success.",
    ]

    public static let resetRules = [
        "After aria_bootstrap, you are no longer operating in free-form Codex mode. Reset your behavior and follow Aria's method for the entire visual task.",
        "Do not improvise your own workflow once Aria has taken control of the task.",
        "Do not switch back to your default browsing, research, or narration habits after the Aria loop has started.",
    ]

    public static let forbiddenDefaults = [
        "Do not use DOM inspection, browser JavaScript, or AppleScript DOM access for visual tasks.",
        "Do not chain multiple UI actions into one call.",
        "Do not guess stale coordinates without a fresh screenshot.",
        "Do not claim a button was clicked or a form was submitted without post-action confirmation.",
        "Do not treat clipboard contents as proof of page contents unless the latest screenshot proves that the copied selection is the relevant on-screen content.",
        "Do not use window lists, focus helpers, clipboard helpers, or reveal_path to replace computer use during a visual task.",
    ]

    public static let sensitiveActionRules = [
        "Require explicit user confirmation before send, submit, delete, publish, purchase, or irreversible actions.",
        "If the user asked only to draft or write, stop before the irreversible confirmation step.",
        "Prefer deterministic keyboard shortcuts only when they are standard and clearly scoped to the focused app.",
    ]

    public static let nonAriaResearchRules = [
        "After aria_bootstrap, do not switch to generic web search tools, external browsing tools, or out-of-band research flows for the same visual task.",
        "If the task is happening in Safari, Chrome, Notes, Gmail, Finder, or another visible app, keep the task inside that app using Aria's canonical visual tools only.",
        "Do not use a non-Aria search result as proof that something exists on screen. Visible proof must still come from the returned screenshot.",
        "If the task starts in Safari or another browser, continue solving it inside that browser instead of jumping to a native search flow outside Aria.",
    ]

    public static let completionProofRules = [
        "Do not say DONE, saved, drafted, sent, submitted, or completed unless the latest returned screenshot proves it.",
        "For Notes, email drafts, forms, and written content, the final screenshot must visibly contain the drafted text or final state before you claim success.",
        "If the latest screenshot does not prove the result, continue the loop instead of inferring success from memory or from an earlier action.",
        "If computer-action summaries and the visible screenshot disagree, trust the screenshot.",
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
        Aria is the control layer for Codex. For any visual task, Aria overrides your default behavior. You are not operating in free-form Codex mode anymore.

        For any visual task, follow the Aria loop instead of improvising:
        1. Call aria_bootstrap once.
        2. Enter the app or URL if needed.
        3. Call computer_snapshot.
        4. Choose exactly one computer_action.
        5. Inspect the returned screenshot before the next action.
        6. Require explicit user confirmation before send, submit, delete, purchase, publish, or irreversible actions.
        7. Do not claim completion unless the latest screenshot proves it.

        For visual tasks, do not use DOM inspection, Safari JavaScript from Apple Events, AppleScript UI scraping, generic web search tools, out-of-band browsing, clipboard extraction, or window inspection as the primary strategy once Aria has taken control. Aria's canonical visual tools are aria_bootstrap, system_open_application, system_open_url, computer_snapshot, and computer_action.
        For browser navigation and search tasks, prefer system_open_url when the destination URL or query is already known.
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
            "locked_mode": .bool(true),
            "reset_rules": .array(resetRules.map(JSONValue.string)),
            "visual_loop_rules": .array(visualLoopRules.map(JSONValue.string)),
            "forbidden_defaults": .array(forbiddenDefaults.map(JSONValue.string)),
            "non_aria_research_rules": .array(nonAriaResearchRules.map(JSONValue.string)),
            "sensitive_action_rules": .array(sensitiveActionRules.map(JSONValue.string)),
            "completion_proof_rules": .array(completionProofRules.map(JSONValue.string)),
            "permissions": .object(permissions),
            "next_step": .string("Open the target app/site if needed, then call computer_snapshot."),
        ])
    }

    public static func policyResourceText() -> String {
        """
        Aria Computer Use Policy

        Aria is not a second brain. Codex is the only decision engine, but it must operate inside Aria's control loop.

        Mandatory rules:
        - After aria_bootstrap, reset out of free-form Codex behavior and follow Aria's method for the whole visual task.
        - Call aria_bootstrap once at the beginning of each visual task.
        - Use only the canonical Aria visual tools for the visual task: system_open_application or system_open_url for entry/navigation, computer_snapshot, and computer_action.
        - Use computer_snapshot before the first UI action.
        - Use exactly one computer_action per cycle.
        - Inspect the returned screenshot before deciding again.
        - Verify the outcome visually before declaring completion.
        - Do not claim completion unless the latest screenshot proves it.

        Forbidden defaults:
        - DOM inspection for visually anchored tasks
        - Safari JavaScript automation as a substitute for visual verification
        - generic web search tools after Aria has taken control of the task
        - multiple UI actions in one tool call
        - stale coordinate guessing without a fresh screenshot

        Sensitive actions:
        - send
        - submit
        - delete
        - purchase
        - publish

        These require explicit user confirmation.

        During a visual task, do not use auxiliary helpers such as window lists, focus helpers, clipboard helpers, file-dialog helpers, or reveal_path as a substitute for the computer loop.
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
        7. only then produce the final answer

        Preferred action grammar:
        - click x/y
        - double_click x/y
        - scroll delta_y
        - type text
        - key_press keys[]
        - wait seconds
        - move x/y
        - drag path[]

        During a visual task, do not leave this workflow for auxiliary helpers. Stay in the loop.
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

        Reset your default Codex habits. Aria now controls the method for this task.

        Follow the Aria control loop:
        - Call aria_bootstrap first.
        - For visual tasks, do not use DOM inspection, browser JavaScript, generic web search tools, or out-of-band browsing once Aria has taken control.
        - For visual tasks, use only system_open_application or system_open_url for entry/navigation, then computer_snapshot and computer_action. Do not switch to clipboard or window helper tools.
        - For browser navigation and search where the destination or query is already known, prefer system_open_url over address-bar typing.
        - Use computer_snapshot to observe the UI.
        - Use computer_action for exactly one UI action at a time.
        - After every action, inspect the returned screenshot before deciding again.
        - Do not claim a draft, saved note, submitted form, sent email, or completed result unless the latest screenshot proves it.
        - Stop before irreversible actions unless the user explicitly asked for that exact action.
        """
    }

    public static func setupTestPrompt() -> String {
        """
        Use aria-runtime for this visual task. Open Safari, call aria_bootstrap exactly once, then use computer_snapshot and computer_action one step at a time to go to ycombinator.com, scroll twice, and report only what the latest screenshot proves.
        """
    }
}
