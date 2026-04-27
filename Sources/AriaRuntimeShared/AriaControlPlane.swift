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
        "Use system_open_application or system_open_url only for initial entry into the target app or site.",
        "After the first computer_action, keep operating the visible app with computer_snapshot and computer_action instead of jumping by URL.",
        "Do not use URL query parameters, deeplinks, mail compose URLs, or search/address-bar shortcuts to fill forms, drafts, recipients, subjects, message bodies, comments, or other visible fields.",
        "For Gmail/email/message tasks, open the app/site, click visible controls, and type into visible fields with computer_action; do not prefill drafts through mail.google.com compose parameters.",
        "Once the visual loop has started, do not switch to clipboard helpers, window-inspection helpers, DOM helpers, or out-of-band research as a substitute for computer use.",
        "For the initial browser navigation or search only, system_open_url is acceptable when the destination URL or search page is already known.",
        "Capture the screen with computer_snapshot before the first UI action.",
        "Execute exactly one UI action per computer_action call.",
        "Inspect the returned screenshot after every action before choosing the next action.",
        "Treat scroll and drag as successful only when the returned screenshot confirms a visual change.",
        "Do not replace mouse work with a keyboard-only loop: when the visible UI requires scrolling or clicking, use scroll/click actions, then retry with adjusted coordinates if the screenshot shows no effect.",
        "For every UI task, behave like a human operator: if the current screen does not yet contain enough information or controls to finish, continue with the obvious visible action such as scrolling, clicking, typing, waiting, closing popups, opening details, or going back.",
        "If the user asks for N concrete things, continue inspecting the visible UI until N concrete things are verified on screen or a visible blocker/error makes it impossible.",
        "computer_action coordinates are screenshot-image pixels with origin at the top-left of the returned screenshot.",
        "For scroll, positive delta_y means scroll down; negative delta_y means scroll up.",
        "Verify completion visually before claiming success.",
    ]

    public static let resetRules = [
        "After aria_bootstrap, you are no longer operating in free-form Codex mode. Reset your behavior and follow Aria's method for the entire visual task.",
        "Do not improvise your own workflow once Aria has taken control of the task.",
        "Do not switch back to your default browsing, research, or narration habits after the Aria loop has started.",
    ]

    public static let forbiddenDefaults = [
        "Do not use DOM inspection, browser JavaScript, or AppleScript DOM access for visual tasks.",
        "Do not use deeplinks or URL query strings as a substitute for clicking and typing in the visible UI.",
        "Do not use mail.google.com compose URLs, mailto-style URLs, or URL parameters such as to, cc, bcc, subject, su, body, message, text, content, or description to draft or send messages.",
        "Do not chain multiple UI actions into one call.",
        "Do not guess stale coordinates without a fresh screenshot.",
        "Do not use repeated Tab/Enter or address-bar retries as a substitute for scrolling and clicking visible content.",
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
        "A URL, result count, filter summary, menu state, loading state, or partial setup screen is not proof that the user's actual objective is complete; proof requires the requested final content or state to be visible.",
    ]

    public static let completionProofRules = [
        "Do not say DONE, saved, drafted, sent, submitted, or completed unless the latest returned screenshot proves it.",
        "For Notes, email drafts, forms, and written content, the final screenshot must visibly contain the drafted text or final state before you claim success.",
        "For tasks asking to find, choose, compare, summarize, fill, create, edit, or verify concrete things, do not claim success until the latest screenshots show the actual requested content, items, or final state.",
        "If the objective requires information or controls not currently visible, continue like a human with scroll, click, wait, close popup, open details, backtrack, or retry instead of stopping at a partial page.",
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
        6. If the objective is not visibly satisfied yet, continue like a human: scroll, click relevant visible controls, open details, close blockers, wait, backtrack, or retry.
        7. Require explicit user confirmation before send, submit, delete, purchase, publish, or irreversible actions.
        8. Do not claim completion unless the latest screenshot proves it.

        For visual tasks, do not use DOM inspection, Safari JavaScript from Apple Events, AppleScript UI scraping, generic web search tools, out-of-band browsing, clipboard extraction, or window inspection as the primary strategy once Aria has taken control. Aria's canonical visual tools are aria_bootstrap, system_open_application, system_open_url, computer_snapshot, and computer_action.
        Use system_open_url only for initial entry/navigation. Do not use URL/deeplink parameters to fill a form, compose an email, set recipients, set message text, submit, or verify a post-action state.
        A URL, count, filter, focus change, or opened page is not completion unless it visibly contains the user's requested final content/state. Keep acting until the concrete objective is visible or visibly blocked.
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
        - Use only the canonical Aria visual tools for the visual task: system_open_application or system_open_url for initial entry/navigation, computer_snapshot, and computer_action.
        - After the first computer_action, keep operating the visible app with computer_action; do not jump to deeplinks or URL-param shortcuts.
        - Never use URL parameters or deeplinks to prefill visible fields, Gmail drafts, recipients, subjects, bodies, comments, messages, or forms.
        - Use computer_snapshot before the first UI action.
        - Use exactly one computer_action per cycle.
        - Inspect the returned screenshot before deciding again.
        - For every task, keep acting like a human until the concrete requested outcome is visible; an intermediate page, URL, count, focus state, or setup state alone is not completion proof.
        - Verify the outcome visually before declaring completion.
        - Do not claim completion unless the latest screenshot proves it.

        Forbidden defaults:
        - DOM inspection for visually anchored tasks
        - Safari JavaScript automation as a substitute for visual verification
        - generic web search tools after Aria has taken control of the task
        - deeplink/form-prefill URLs after Aria has taken control of the task
        - multiple UI actions in one tool call
        - stale coordinate guessing without a fresh screenshot
        - stopping on an intermediate state without reaching the user's concrete visible objective

        Sensitive actions:
        - send
        - submit
        - delete
        - purchase
        - publish

        These require explicit user confirmation.

        During a visual task, do not use auxiliary helpers such as window lists, focus helpers, clipboard helpers, file-dialog helpers, reveal_path, or deeplink URL tricks as a substitute for the computer loop.
        """
    }

    public static func workflowResourceText() -> String {
        """
        Aria Visual Workflow

        1. aria_bootstrap
        2. system_open_application or system_open_url if initial entry is needed
        3. computer_snapshot
        4. computer_action with exactly one action
        5. inspect returned screenshot
        6. if the objective is not visible yet, continue with human-like actions: scroll, click relevant controls, open details, wait, close blockers, backtrack, or retry
        7. repeat until visually verified
        8. only then produce the final answer

        Preferred action grammar:
        - click x/y
        - double_click x/y
        - scroll delta_y (positive = down, negative = up)
        - type text
        - key_press keys[]
        - wait seconds
        - move x/y
        - drag path[]

        During a visual task, do not leave this workflow for auxiliary helpers or URL/deeplink shortcuts. Stay in the loop.
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
        - For visual tasks, use only system_open_application or system_open_url for initial entry/navigation, then computer_snapshot and computer_action. Do not switch to clipboard or window helper tools.
        - Use system_open_url only to enter the target site/app or an initial known URL. After the first computer_action, keep using visible click/type/scroll actions.
        - Never use deeplinks or URL query parameters to fill visible fields. For Gmail/email/message/form tasks, click visible controls and type into visible fields instead of using URL params such as to, body, su, subject, message, text, content, or description.
        - Use computer_snapshot to observe the UI.
        - Use computer_action for exactly one UI action at a time.
        - Use screenshot-image coordinates from the latest screenshot. Positive scroll delta_y scrolls down; negative scrolls up.
        - If the visible UI requires mouse work, use scroll/click actions instead of falling back to a keyboard-only loop; retry with adjusted coordinates when the screenshot shows no effect.
        - For every UI task, act like a human operator: if the current screen is only an intermediate step, keep going with scroll/click/type/wait/backtrack until the requested final content or state is visible.
        - If the user asks for N concrete items/options/messages/files/results, continue until N concrete visible items with useful details are found, or say exactly what visible blocker prevents it.
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
