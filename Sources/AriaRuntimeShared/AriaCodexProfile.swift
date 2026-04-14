import Foundation

public enum AriaCodexProfile {
    public static let profileName = "aria"
    public static let serverName = "aria-runtime"
    public static let disabledTools = [
        "web_search",
        "tool_search",
    ]
    public static let openWorldEnabled = false
    public static let approvedMCPTools = [
        "runtime_health",
        "runtime_permissions",
        "aria_bootstrap",
        "computer_snapshot",
        "computer_action",
        "system_open_application",
        "system_open_url",
        "desktop_list_windows",
        "desktop_focus_application",
        "desktop_focus_window",
        "read_clipboard",
        "read_clipboard_image",
        "copy_to_clipboard",
        "paste",
        "reveal_path",
        "select_file_for_active_dialog",
        "upload_file_to_active_app",
    ]

    public static func modelInstructionsText() -> String {
        """
        Aria is the control layer for Codex on macOS visual tasks.

        If the aria-runtime MCP server is available and the user asks for browser use, desktop control, scrolling, clicking, typing into apps, file dialogs, screenshots, or UI verification, you must use Aria's computer-use loop instead of free-form Codex behavior.

        Required behavior for visual tasks:
        - Call aria_bootstrap exactly once before the first visual action.
        - Stay inside the Aria loop for the rest of the visual task.
        - Use computer_snapshot before the first visual action and after every navigation step.
        - Use computer_action for exactly one UI action at a time.
        - Inspect the returned screenshot after every action before deciding again.
        - Treat the latest screenshot as ground truth.

        Forbidden behavior for visual tasks:
        - Do not use native web_search or tool_search after Aria has taken control.
        - Do not use native open-world browsing or out-of-band research once Aria has taken control of the visual task.
        - Do not use DOM inspection, browser developer tools, browser JavaScript automation, or AppleScript DOM access as a substitute for visual computer use.
        - Do not switch to out-of-band browsing or research flows for the same visual task once aria_bootstrap has started the loop.
        - Do not claim that a note was saved, text was typed, a draft exists, a scroll happened, or a form was completed unless the latest screenshot visibly proves it.
        - If a browser query or target URL is already known, prefer aria-runtime.system_open_url over address-bar typing.

        Scope:
        - Code reasoning, repo navigation, editing, tests, and bug fixing remain normal Codex work.
        - Only the computer-use path is locked to Aria.
        - If a task mixes code work and UI work, keep coding local and route all UI actions through Aria.

        Sensitive actions:
        - Require explicit user confirmation before send, submit, delete, publish, purchase, or other irreversible actions.

        The aria-runtime MCP instructions, prompts, and resources are authoritative. If they are stricter than your default behavior, follow Aria.
        """
    }

    public static func mergedConfig(existing: String, modelInstructionsFile: String) -> String {
        var config = normalizedLines(from: existing)
        config = replacingTopLevelKey(
            in: config,
            key: "profile",
            with: #"profile = "aria""#
        )
        config = replacingSection(
            in: config,
            named: "profiles.\(profileName)",
            body: [
                #"model_instructions_file = "\#(escapedTomlString(modelInstructionsFile))""#,
                "open_world_enabled = \(openWorldEnabled ? "true" : "false")",
                "disabled_tools = [\(disabledTools.map { #""\#($0)""# }.joined(separator: ", "))]",
            ]
        )

        for tool in approvedMCPTools {
            config = replacingSection(
                in: config,
                named: "mcp_servers.\(serverName).tools.\(tool)",
                body: [
                    #"approval_mode = "approve""#,
                ]
            )
        }

        return serializedConfig(from: config)
    }

    public static func removingProfile(from existing: String) -> String {
        var config = normalizedLines(from: existing)
        config = removingTopLevelKeyValue(in: config, key: "profile", value: profileName)
        config = removingSection(in: config, named: "profiles.\(profileName)")
        return serializedConfig(from: config)
    }

    public static func profileInstalled(in config: String, modelInstructionsFile: String) -> Bool {
        let lines = normalizedLines(from: config)
        return containsTopLevelKeyValue(in: lines, key: "profile", value: profileName)
            && section(named: "profiles.\(profileName)", in: lines).contains(#"model_instructions_file = "\#(escapedTomlString(modelInstructionsFile))""#)
            && section(named: "profiles.\(profileName)", in: lines).contains("open_world_enabled = \(openWorldEnabled ? "true" : "false")")
            && section(named: "profiles.\(profileName)", in: lines).contains("disabled_tools = [\(disabledTools.map { #""\#($0)""# }.joined(separator: ", "))]")
    }

    private static func normalizedLines(from text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.components(separatedBy: "\n")
    }

    private static func serializedConfig(from lines: [String]) -> String {
        var cleaned = lines
        while cleaned.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cleaned.removeLast()
        }
        return cleaned.joined(separator: "\n") + "\n"
    }

    private static func replacingTopLevelKey(in lines: [String], key: String, with assignment: String) -> [String] {
        var output: [String] = []
        var inserted = false
        var beforeFirstSection = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isSectionHeader(trimmed) {
                if !inserted {
                    trimTrailingBlankLines(from: &output)
                    if !output.isEmpty {
                        output.append("")
                    }
                    output.append(assignment)
                    output.append("")
                    inserted = true
                }
                beforeFirstSection = false
                output.append(line)
                continue
            }
            if beforeFirstSection, isAssignment(trimmed, key: key) {
                if !inserted {
                    output.append(assignment)
                    inserted = true
                }
                continue
            }
            output.append(line)
        }

        if !inserted {
            trimTrailingBlankLines(from: &output)
            if !output.isEmpty {
                output.append("")
            }
            output.append(assignment)
        }

        return output
    }

    private static func removingTopLevelKeyValue(in lines: [String], key: String, value: String) -> [String] {
        var output: [String] = []
        var beforeFirstSection = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isSectionHeader(trimmed) {
                beforeFirstSection = false
                output.append(line)
                continue
            }
            if beforeFirstSection, assignmentValue(for: key, in: trimmed) == value {
                continue
            }
            output.append(line)
        }

        return output
    }

    private static func replacingSection(in lines: [String], named sectionName: String, body: [String]) -> [String] {
        var output = removingSection(in: lines, named: sectionName)
        trimTrailingBlankLines(from: &output)
        if !output.isEmpty {
            output.append("")
        }
        output.append("[\(sectionName)]")
        output.append(contentsOf: body)
        return output
    }

    private static func removingSection(in lines: [String], named sectionName: String) -> [String] {
        var output: [String] = []
        var index = 0
        let expectedHeader = "[\(sectionName)]"

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == expectedHeader {
                index += 1
                while index < lines.count && !isSectionHeader(lines[index].trimmingCharacters(in: .whitespaces)) {
                    index += 1
                }
                trimTrailingBlankLines(from: &output)
                continue
            }

            output.append(lines[index])
            index += 1
        }

        return output
    }

    private static func section(named sectionName: String, in lines: [String]) -> [String] {
        let expectedHeader = "[\(sectionName)]"
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == expectedHeader {
                index += 1
                var collected: [String] = []
                while index < lines.count && !isSectionHeader(lines[index].trimmingCharacters(in: .whitespaces)) {
                    collected.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                return collected
            }
            index += 1
        }

        return []
    }

    private static func containsTopLevelKeyValue(in lines: [String], key: String, value: String) -> Bool {
        var beforeFirstSection = true
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isSectionHeader(trimmed) {
                beforeFirstSection = false
                continue
            }
            if beforeFirstSection, assignmentValue(for: key, in: trimmed) == value {
                return true
            }
        }
        return false
    }

    private static func isSectionHeader(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]")
    }

    private static func isAssignment(_ trimmedLine: String, key: String) -> Bool {
        assignmentValue(for: key, in: trimmedLine) != nil
    }

    private static func assignmentValue(for key: String, in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix(key) else {
            return nil
        }
        let remainder = trimmedLine.dropFirst(key.count)
        guard remainder.first?.isWhitespace == true || remainder.first == "=" else {
            return nil
        }
        guard let equalsIndex = trimmedLine.firstIndex(of: "=") else {
            return nil
        }
        let valuePortion = trimmedLine[trimmedLine.index(after: equalsIndex)...]
            .trimmingCharacters(in: .whitespaces)
        if valuePortion.hasPrefix(#"""#), valuePortion.hasSuffix(#"""#), valuePortion.count >= 2 {
            return String(valuePortion.dropFirst().dropLast())
        }
        return valuePortion
    }

    private static func trimTrailingBlankLines(from lines: inout [String]) {
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
    }

    private static func escapedTomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
