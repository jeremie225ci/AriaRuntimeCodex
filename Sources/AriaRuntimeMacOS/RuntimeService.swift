import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import AriaRuntimeShared

private struct CapturedScreen {
    let image: CGImage
    let pngData: Data
}

private struct VisualVerificationResult {
    let actionType: String
    let required: Bool
    let changed: Bool
    let confirmed: Bool
    let changeRatio: Double
    let averageDelta: Double
    let thresholdRatio: Double
    let thresholdDelta: Double
    let reason: String

    func payload() -> JSONValue {
        .object([
            "action_type": .string(actionType),
            "required": .bool(required),
            "changed": .bool(changed),
            "confirmed": .bool(confirmed),
            "change_ratio": .number(changeRatio),
            "average_delta": .number(averageDelta),
            "threshold_ratio": .number(thresholdRatio),
            "threshold_delta": .number(thresholdDelta),
            "reason": .string(reason),
        ])
    }
}

public final class MacOSRuntimeService: @unchecked Sendable {
    public let version = "1.0.0"

    public init() {}

    public func toolDescriptors() -> [ToolDescriptor] {
        [
            ToolDescriptor(
                name: "runtime_health",
                description: "Return daemon metadata and runtime readiness.",
                inputSchema: .object([:])
            ),
            ToolDescriptor(
                name: "runtime_permissions",
                description: "Return macOS permission status required for Aria runtime automation.",
                inputSchema: .object([:])
            ),
            ToolDescriptor(
                name: "aria_bootstrap",
                description: "Call exactly once at the start of each visual/UI task. This resets Codex into Aria-controlled mode and returns the mandatory operating rules for the whole task.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "task": .object(["type": .string("string")]),
                    ]),
                    "additionalProperties": .bool(false),
                ])
            ),
            ToolDescriptor(
                name: "computer_snapshot",
                description: "Capture the current screen and return the image plus Aria loop guidance. Requires aria_bootstrap first. Use before the first UI action, after app/site entry, and whenever the latest screen proof is insufficient.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "goal": .object(["type": .string("string")]),
                    ]),
                    "additionalProperties": .bool(false),
                ])
            ),
            ToolDescriptor(
                name: "computer_action",
                description: "The canonical Aria UI tool. Execute one UI action, or up to three tightly related UI actions via the actions array, using coordinates from the latest screenshot image. Aria captures one post-action screenshot to inspect before the next call. For scroll, positive delta_y scrolls down. Requires aria_bootstrap and a fresh computer_snapshot first. Do not leave the Aria loop or claim completion without screenshot proof.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "type": .object([
                                    "type": .string("string"),
                                    "enum": .array(AriaControlPlane.allowedComputerActionTypes.map(JSONValue.string)),
                                ]),
                                "x": .object(["type": .string("number")]),
                                "y": .object(["type": .string("number")]),
                                "button": .object(["type": .string("string"), "enum": .array([.string("left"), .string("right")])]),
                                "delta_x": .object(["type": .string("number")]),
                                "delta_y": .object(["type": .string("number")]),
                                "text": .object(["type": .string("string")]),
                                "keys": .object([
                                    "type": .string("array"),
                                    "items": .object(["type": .string("string")]),
                                ]),
                                "seconds": .object(["type": .string("number")]),
                                "path": .object([
                                    "type": .string("array"),
                                    "items": .object([
                                        "type": .string("object"),
                                        "properties": .object([
                                            "x": .object(["type": .string("number")]),
                                            "y": .object(["type": .string("number")]),
                                        ]),
                                        "required": .array([.string("x"), .string("y")]),
                                    ]),
                                ]),
                            ]),
                            "required": .array([.string("type")]),
                        ]),
                        "actions": .object([
                            "type": .string("array"),
                            "minItems": .number(1),
                            "maxItems": .number(3),
                            "items": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "type": .object([
                                        "type": .string("string"),
                                        "enum": .array(AriaControlPlane.allowedComputerActionTypes.map(JSONValue.string)),
                                    ]),
                                    "x": .object(["type": .string("number")]),
                                    "y": .object(["type": .string("number")]),
                                    "button": .object(["type": .string("string"), "enum": .array([.string("left"), .string("right")])]),
                                    "delta_x": .object(["type": .string("number")]),
                                    "delta_y": .object(["type": .string("number")]),
                                    "text": .object(["type": .string("string")]),
                                    "keys": .object([
                                        "type": .string("array"),
                                        "items": .object(["type": .string("string")]),
                                    ]),
                                    "seconds": .object(["type": .string("number")]),
                                    "path": .object([
                                        "type": .string("array"),
                                        "items": .object([
                                            "type": .string("object"),
                                            "properties": .object([
                                                "x": .object(["type": .string("number")]),
                                                "y": .object(["type": .string("number")]),
                                            ]),
                                            "required": .array([.string("x"), .string("y")]),
                                        ]),
                                    ]),
                                ]),
                                "required": .array([.string("type")]),
                            ]),
                        ]),
                        "goal": .object(["type": .string("string")]),
                    ]),
                    "additionalProperties": .bool(false),
                ])
            ),
            ToolDescriptor(
                name: "system_open_application",
                description: "Launch an application by name, bundle identifier, or full path. Requires aria_bootstrap first. After opening, stay in the Aria loop and call computer_snapshot before acting visually.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string")]),
                        "bundle_id": .object(["type": .string("string")]),
                        "path": .object(["type": .string("string")]),
                    ]),
                ])
            ),
            ToolDescriptor(
                name: "system_open_url",
                description: "Open an initial entry URL using the user's default browser. Requires aria_bootstrap first. Do not use URL query parameters or deeplinks to fill forms, compose messages, set recipients/subjects/bodies, submit, or verify state. After navigation, stay in the Aria loop and call computer_snapshot before any visual interaction.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("url")]),
                ])
            ),
            ToolDescriptor(
                name: "desktop_list_windows",
                description: "List visible on-screen windows so Codex can identify the current app and window state.",
                inputSchema: .object([:])
            ),
            ToolDescriptor(
                name: "desktop_focus_application",
                description: "Focus a running macOS application by name or bundle identifier. Requires aria_bootstrap first. After focusing, call computer_snapshot before acting visually.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string")]),
                        "bundle_id": .object(["type": .string("string")]),
                    ]),
                ])
            ),
            ToolDescriptor(
                name: "desktop_focus_window",
                description: "Focus a visible macOS window by title and optional owner name. Requires aria_bootstrap first. After focusing, call computer_snapshot before acting visually.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "owner_name": .object(["type": .string("string")]),
                        "bundle_id": .object(["type": .string("string")]),
                        "query": .object(["type": .string("string")]),
                    ]),
                ])
            ),
            ToolDescriptor(
                name: "read_clipboard",
                description: "Read the current macOS text clipboard.",
                inputSchema: .object([:])
            ),
            ToolDescriptor(
                name: "read_clipboard_image",
                description: "Read the current macOS clipboard image and return it as MCP image content when available.",
                inputSchema: .object([:])
            ),
            ToolDescriptor(
                name: "copy_to_clipboard",
                description: "Write text to the macOS clipboard.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("text")]),
                ])
            ),
            ToolDescriptor(
                name: "paste",
                description: "Paste the current clipboard into the focused macOS app. Requires aria_bootstrap first. After pasting, call computer_snapshot before the next visual decision.",
                inputSchema: .object([:])
            ),
            ToolDescriptor(
                name: "select_file_for_active_dialog",
                description: "Select an existing file in the frontmost macOS open/upload dialog using the standard Go to Folder flow. Requires aria_bootstrap first. After selection, call computer_snapshot before the next visual decision.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("path")]),
                ])
            ),
            ToolDescriptor(
                name: "upload_file_to_active_app",
                description: "Alias for selecting a file in the frontmost macOS upload/open dialog. Requires aria_bootstrap first. After selection, call computer_snapshot before the next visual decision.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("path")]),
                ])
            ),
            ToolDescriptor(
                name: "reveal_path",
                description: "Reveal an existing file or directory in Finder. Requires aria_bootstrap first. After Finder opens, call computer_snapshot before acting visually.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("path")]),
                ])
            ),
        ]
    }

    public func handle(_ request: RuntimeRequest) -> RuntimeResponse {
        do {
            switch request.method {
            case .health:
                return .success(id: request.id, result: healthPayload())
            case .permissions:
                return .success(id: request.id, result: permissionsPayload())
            case .requestPermissions:
                return .success(id: request.id, result: requestPermissionsPayload())
            case .tools:
                let tools = toolDescriptors().map { descriptor in
                    JSONValue.object([
                        "name": .string(descriptor.name),
                        "description": .string(descriptor.description),
                        "inputSchema": descriptor.inputSchema,
                    ])
                }
                return .success(id: request.id, result: .object(["tools": .array(tools)]))
            case .invoke:
                guard
                    let params = request.params?.objectValue,
                    let tool = params["tool"]?.stringValue
                else {
                    throw RuntimeProtocolError.invalidParameters("Missing tool in runtime.invoke params")
                }
                let arguments = params["arguments"]?.objectValue ?? [:]
                let result = try invoke(tool: tool, arguments: arguments)
                return .success(id: request.id, result: result)
            }
        } catch let error as RuntimeProtocolError {
            switch error {
            case .invalidParameters:
                return .failure(id: request.id, code: "invalid_parameters", message: error.description)
            case .toolNotFound:
                return .failure(id: request.id, code: "tool_not_found", message: error.description)
            case .runtimeFailure:
                return .failure(id: request.id, code: "runtime_failure", message: error.description)
            }
        } catch {
            return .failure(id: request.id, code: "internal_error", message: String(describing: error))
        }
    }

    private func invoke(tool: String, arguments: [String: JSONValue]) throws -> JSONValue {
        switch tool {
        case "runtime_health":
            return healthPayload()
        case "runtime_permissions":
            return permissionsPayload()
        case "aria_bootstrap":
            return ariaBootstrap()
        case "computer_snapshot":
            return try computerSnapshot(goal: arguments["goal"]?.stringValue)
        case "computer_action":
            return try computerAction(arguments: arguments)
        case "system_open_application":
            let descriptor = try openApplication(arguments: arguments)
            return .object([
                "ok": .bool(true),
                "application": .string(descriptor),
                "next_step": .string("Call computer_snapshot before the first visual action."),
            ])
        case "system_open_url":
            let urlValue = try requiredString(arguments, key: "url")
            try openURL(urlValue)
            return .object([
                "ok": .bool(true),
                "url": .string(urlValue),
                "next_step": .string("Call computer_snapshot after the page finishes loading."),
            ])
        case "desktop_list_windows":
            return listWindows()
        case "desktop_focus_application":
            try focusApplication(arguments: arguments)
            let descriptor = arguments["bundle_id"]?.stringValue ?? arguments["name"]?.stringValue ?? ""
            return .object([
                "ok": .bool(true),
                "application": .string(descriptor),
                "next_step": .string("Call computer_snapshot before the next visual action."),
            ])
        case "desktop_focus_window":
            let focused = try focusWindow(arguments: arguments)
            var payload: [String: JSONValue] = [
                "ok": .bool(true),
                "next_step": .string("Call computer_snapshot before the next visual action."),
            ]
            for (key, value) in focused {
                payload[key] = value
            }
            return .object(payload)
        case "read_clipboard":
            return try readClipboard()
        case "read_clipboard_image":
            return try readClipboardImage()
        case "copy_to_clipboard":
            let text = try requiredString(arguments, key: "text")
            try writeClipboard(text)
            return .object([
                "ok": .bool(true),
                "length": .number(Double(text.count)),
            ])
        case "paste":
            try pasteClipboard()
            return .object([
                "ok": .bool(true),
                "next_step": .string("Call computer_snapshot before the next visual action."),
            ])
        case "select_file_for_active_dialog":
            let rawPath = try requiredString(arguments, key: "path")
            let payload = try selectFileForActiveDialog(rawPath)
            return .object(payload.merging([
                "ok": .bool(true),
                "next_step": .string("Call computer_snapshot before the next visual action."),
            ]) { _, new in new })
        case "upload_file_to_active_app":
            let rawPath = try requiredString(arguments, key: "path")
            let payload = try selectFileForActiveDialog(rawPath)
            return .object(payload.merging([
                "ok": .bool(true),
                "next_step": .string("Call computer_snapshot before the next visual action."),
            ]) { _, new in new })
        case "reveal_path":
            let rawPath = try requiredString(arguments, key: "path")
            try revealPath(rawPath)
            return .object([
                "ok": .bool(true),
                "path": .string(rawPath),
                "next_step": .string("Call computer_snapshot after Finder is visible if you need visual interaction."),
            ])
        default:
            throw RuntimeProtocolError.toolNotFound(tool)
        }
    }

    private func ariaBootstrap() -> JSONValue {
        AriaControlPlane.bootstrapPayload(
            version: version,
            permissions: permissionState(),
            availableTools: toolDescriptors().map(\.name)
        )
    }

    private func computerSnapshot(goal: String?) throws -> JSONValue {
        let frame = try captureScreen()
        var payload = screenshotPayload(from: frame)
        payload["mode"] = .string("computer_snapshot")
        payload["windows"] = listWindows()["windows"] ?? .array([])
        payload["locked_mode"] = .bool(true)
        payload["reset_rules"] = .array(AriaControlPlane.resetRules.map(JSONValue.string))
        payload["visual_loop_rules"] = .array(AriaControlPlane.visualLoopRules.map(JSONValue.string))
        payload["forbidden_defaults"] = .array(AriaControlPlane.forbiddenDefaults.map(JSONValue.string))
        payload["non_aria_research_rules"] = .array(AriaControlPlane.nonAriaResearchRules.map(JSONValue.string))
        payload["sensitive_action_rules"] = .array(AriaControlPlane.sensitiveActionRules.map(JSONValue.string))
        payload["completion_proof_rules"] = .array(AriaControlPlane.completionProofRules.map(JSONValue.string))
        payload["next_step"] = .string("Inspect the screenshot, then choose one computer_action call with up to three tightly related actions.")
        if let goal, !goal.isEmpty {
            payload["goal"] = .string(goal)
        }
        return .object(payload)
    }

    private func computerAction(arguments: [String: JSONValue]) throws -> JSONValue {
        let actions = try computerActions(from: arguments)
        let actionTypes = try actions.map { try requiredString($0, key: "type") }
        let goal = arguments["goal"]?.stringValue
        let beforeFrame = try captureScreen()
        var executedActions: [[String: JSONValue]] = []
        for (index, action) in actions.enumerated() {
            let executedAction = try executeComputerAction(action)
            executedActions.append(executedAction)
            settleAfterAction(actionTypes[index])
        }
        let afterFrame = try captureScreen()
        let verification = try verifyVisualOutcome(
            actionTypes: actionTypes,
            actions: actions,
            goal: goal,
            before: beforeFrame.image,
            after: afterFrame.image
        )
        var payload = screenshotPayload(from: afterFrame)
        payload["mode"] = .string("computer_action")
        payload["locked_mode"] = .bool(true)
        payload["reset_rules"] = .array(AriaControlPlane.resetRules.map(JSONValue.string))
        payload["ok"] = .bool(verification.confirmed || !verification.required)
        payload["executed_actions"] = .array(executedActions.map(JSONValue.object))
        if executedActions.count == 1, let executedAction = executedActions.first {
            payload["executed_action"] = .object(executedAction)
        }
        payload["visual_loop_rules"] = .array(AriaControlPlane.visualLoopRules.map(JSONValue.string))
        payload["forbidden_defaults"] = .array(AriaControlPlane.forbiddenDefaults.map(JSONValue.string))
        payload["non_aria_research_rules"] = .array(AriaControlPlane.nonAriaResearchRules.map(JSONValue.string))
        payload["completion_proof_rules"] = .array(AriaControlPlane.completionProofRules.map(JSONValue.string))
        payload["visual_confirmation"] = verification.payload()
        if let goal, !goal.isEmpty {
            payload["goal"] = .string(goal)
        }
        if verification.required && !verification.confirmed {
            payload["error"] = .object([
                "code": .string("visual_confirmation_failed"),
                "message": .string(verification.reason),
            ])
            payload["next_step"] = .string("The expected visual change was not confirmed. Inspect the screenshot and choose a different action.")
        } else {
            payload["next_step"] = .string("Inspect this returned screenshot before choosing the next action.")
        }
        return .object(payload)
    }

    private func computerActions(from arguments: [String: JSONValue]) throws -> [[String: JSONValue]] {
        if let rawActions = arguments["actions"]?.arrayValue {
            guard !rawActions.isEmpty else {
                throw RuntimeProtocolError.invalidParameters("computer_action actions array cannot be empty")
            }
            guard rawActions.count <= 3 else {
                throw RuntimeProtocolError.invalidParameters("computer_action supports at most 3 actions per call")
            }
            return try rawActions.enumerated().map { index, item in
                guard let action = item.objectValue else {
                    throw RuntimeProtocolError.invalidParameters("computer_action actions[\(index)] must be an object")
                }
                _ = try requiredString(action, key: "type")
                return action
            }
        }

        let action = try requiredObject(arguments, key: "action")
        _ = try requiredString(action, key: "type")
        return [action]
    }

    private func healthPayload() -> JSONValue {
        .object([
            "service": .string("aria-runtime"),
            "version": .string(version),
            "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            "socket_path": .string(RuntimePaths.socketURL.path),
            "permissions": permissionsPayload(),
        ])
    }

    private func permissionsPayload() -> JSONValue {
        .object(permissionState())
    }

    private func requestPermissionsPayload() -> JSONValue {
        let before = permissionState()
        let requestedAccessibility = !currentAccessibilityTrusted()
        let requestedScreenRecording = !screenRecordingTrusted()

        if requestedAccessibility {
            _ = currentAccessibilityTrusted(prompt: true)
        }

        if requestedScreenRecording {
            _ = requestScreenRecordingAccess()
        }

        let after = permissionState()
        return .object([
            "before": .object(before),
            "after": .object(after),
            "requested_accessibility_prompt": .bool(requestedAccessibility),
            "requested_screen_recording_prompt": .bool(requestedScreenRecording),
            "restart_required": .bool(requestedAccessibility || requestedScreenRecording),
        ])
    }

    private func screenRecordingTrusted() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    private func ensureAccessibility() throws {
        guard currentAccessibilityTrusted() else {
            throw RuntimeProtocolError.runtimeFailure("Accessibility permission is required for desktop automation.")
        }
    }

    private func permissionState() -> [String: JSONValue] {
        [
            "accessibility_trusted": .bool(currentAccessibilityTrusted()),
            "screen_recording_trusted": .bool(screenRecordingTrusted()),
            "automation_status": .string("unknown"),
        ]
    }

    private func currentAccessibilityTrusted(prompt: Bool = false) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }

        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestScreenRecordingAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }

    private func requiredString(_ arguments: [String: JSONValue], key: String) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw RuntimeProtocolError.invalidParameters("Missing required string parameter: \(key)")
        }
        return value
    }

    private func requiredDouble(_ arguments: [String: JSONValue], key: String) throws -> Double {
        if let value = arguments[key]?.doubleValue {
            return value
        }
        if let value = arguments[key]?.intValue {
            return Double(value)
        }
        throw RuntimeProtocolError.invalidParameters("Missing required numeric parameter: \(key)")
    }

    private func requiredObject(_ arguments: [String: JSONValue], key: String) throws -> [String: JSONValue] {
        guard let value = arguments[key]?.objectValue else {
            throw RuntimeProtocolError.invalidParameters("Missing required object parameter: \(key)")
        }
        return value
    }

    private func captureScreenshot() throws -> JSONValue {
        guard screenRecordingTrusted() else {
            throw RuntimeProtocolError.runtimeFailure("Screen Recording permission is required for screenshots.")
        }
        return .object(screenshotPayload(from: try captureScreen()))
    }

    private func captureScreen() throws -> CapturedScreen {
        guard screenRecordingTrusted() else {
            throw RuntimeProtocolError.runtimeFailure("Screen Recording permission is required for screenshots.")
        }
        return try runOnMain {
            guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
                throw RuntimeProtocolError.runtimeFailure("Unable to capture the main display.")
            }
            let representation = NSBitmapImageRep(cgImage: image)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                throw RuntimeProtocolError.runtimeFailure("Unable to encode screenshot as PNG.")
            }
            return CapturedScreen(image: image, pngData: data)
        }
    }

    private func screenshotPayload(from frame: CapturedScreen) -> [String: JSONValue] {
        [
            "mime": .string("image/png"),
            "width": .number(Double(frame.image.width)),
            "height": .number(Double(frame.image.height)),
            "image_base64": .string(frame.pngData.base64EncodedString()),
            "coordinate_system": .object([
                "origin": .string("top_left"),
                "units": .string("screenshot_image_pixels"),
                "note": .string("Use coordinates from this returned screenshot. Aria maps screenshot pixels to macOS display points internally."),
                "scroll_delta_y": .string("positive_scrolls_down_negative_scrolls_up"),
            ]),
        ]
    }

    private func executeComputerAction(_ action: [String: JSONValue]) throws -> [String: JSONValue] {
        let actionType = try requiredString(action, key: "type")
        switch actionType {
        case "click":
            let x = try requiredDouble(action, key: "x")
            let y = try requiredDouble(action, key: "y")
            let button = action["button"]?.stringValue ?? "left"
            let displayPoint = screenshotCoordinateToDisplayPoint(x: x, y: y)
            try ensureAccessibility()
            try click(at: displayPoint, button: button, clickCount: 1)
            return [
                "type": .string(actionType),
                "x": .number(x),
                "y": .number(y),
                "display_x": .number(displayPoint.x),
                "display_y": .number(displayPoint.y),
                "button": .string(button),
            ]
        case "double_click":
            let x = try requiredDouble(action, key: "x")
            let y = try requiredDouble(action, key: "y")
            let displayPoint = screenshotCoordinateToDisplayPoint(x: x, y: y)
            try ensureAccessibility()
            try click(at: displayPoint, button: "left", clickCount: 2)
            return [
                "type": .string(actionType),
                "x": .number(x),
                "y": .number(y),
                "display_x": .number(displayPoint.x),
                "display_y": .number(displayPoint.y),
            ]
        case "scroll":
            let hasDeltaX = action["delta_x"]?.doubleValue != nil
            let hasDeltaY = action["delta_y"]?.doubleValue != nil
            let deltaX = action["delta_x"]?.doubleValue ?? 0
            let deltaY = hasDeltaY ? (action["delta_y"]?.doubleValue ?? 0) : (hasDeltaX ? 0 : 620)
            try ensureAccessibility()
            if let x = action["x"]?.doubleValue, let y = action["y"]?.doubleValue {
                try moveMouse(to: screenshotCoordinateToDisplayPoint(x: x, y: y))
                usleep(60_000)
            }
            try scroll(deltaX: Int32(deltaX.rounded()), deltaY: Int32(deltaY.rounded()))
            return [
                "type": .string(actionType),
                "delta_x": .number(deltaX),
                "delta_y": .number(deltaY),
            ]
        case "type":
            let text = try requiredString(action, key: "text")
            try ensureAccessibility()
            try typeText(text)
            return [
                "type": .string(actionType),
                "text_length": .number(Double(text.count)),
            ]
        case "key_press":
            guard let keys = action["keys"]?.arrayValue?.compactMap(\.stringValue), !keys.isEmpty else {
                throw RuntimeProtocolError.invalidParameters("computer_action key_press requires a non-empty keys array")
            }
            try ensureAccessibility()
            try keyPress(keys)
            return [
                "type": .string(actionType),
                "keys": .array(keys.map(JSONValue.string)),
            ]
        case "wait":
            let seconds = action["seconds"]?.doubleValue ?? 1
            usleep(useconds_t(max(0.05, min(seconds, 10.0)) * 1_000_000))
            return [
                "type": .string(actionType),
                "seconds": .number(seconds),
            ]
        case "move":
            let x = try requiredDouble(action, key: "x")
            let y = try requiredDouble(action, key: "y")
            let displayPoint = screenshotCoordinateToDisplayPoint(x: x, y: y)
            try ensureAccessibility()
            try moveMouse(to: displayPoint)
            return [
                "type": .string(actionType),
                "x": .number(x),
                "y": .number(y),
                "display_x": .number(displayPoint.x),
                "display_y": .number(displayPoint.y),
            ]
        case "drag":
            guard let path = action["path"]?.arrayValue, !path.isEmpty else {
                throw RuntimeProtocolError.invalidParameters("computer_action drag requires a non-empty path array")
            }
            let screenshotPoints = try path.map { item -> CGPoint in
                guard let point = item.objectValue else {
                    throw RuntimeProtocolError.invalidParameters("computer_action drag path items must be objects")
                }
                return CGPoint(
                    x: try requiredDouble(point, key: "x"),
                    y: try requiredDouble(point, key: "y")
                )
            }
            let displayPoints = screenshotPoints.map { point in
                screenshotCoordinateToDisplayPoint(x: point.x, y: point.y)
            }
            try ensureAccessibility()
            try drag(along: displayPoints)
            return [
                "type": .string(actionType),
                "path": .array(screenshotPoints.map { point in
                    .object([
                        "x": .number(point.x),
                        "y": .number(point.y),
                    ])
                }),
                "display_path": .array(displayPoints.map { point in
                    .object([
                        "x": .number(point.x),
                        "y": .number(point.y),
                    ])
                }),
            ]
        default:
            throw RuntimeProtocolError.invalidParameters(
                "Unsupported computer_action type: \(actionType). Allowed types: \(AriaControlPlane.allowedComputerActionTypes.joined(separator: ", "))"
            )
        }
    }

    private func settleAfterAction(_ actionType: String) {
        let microseconds: useconds_t
        switch actionType {
        case "scroll", "drag":
            microseconds = 220_000
        case "click", "double_click", "type", "key_press":
            microseconds = 160_000
        case "move":
            microseconds = 80_000
        case "wait":
            microseconds = 0
        default:
            microseconds = 120_000
        }
        if microseconds > 0 {
            usleep(microseconds)
        }
    }

    private func verifyVisualOutcome(actionTypes: [String], actions: [[String: JSONValue]], goal: String?, before: CGImage, after: CGImage) throws -> VisualVerificationResult {
        guard actionTypes.count == actions.count, !actionTypes.isEmpty else {
            throw RuntimeProtocolError.invalidParameters("computer_action visual verification requires at least one executed action")
        }

        if actionTypes.count == 1, let actionType = actionTypes.first, let action = actions.first {
            return try verifyVisualOutcome(
                actionType: actionType,
                action: action,
                goal: goal,
                before: before,
                after: after
            )
        }

        let batchActionType = "batch(\(actionTypes.joined(separator: ",")))"
        var shouldRequireVisibleChange = false
        var thresholdRatio = 0.0022
        var thresholdDelta = 0.0012

        for (actionType, action) in zip(actionTypes, actions) {
            let requirement = verificationRequirement(for: actionType)
            let required = requirement.requiredByDefault
                || goalRequiresVisibleChange(actionType: actionType, action: action, goal: goal)
            if required {
                shouldRequireVisibleChange = true
                if requirement.thresholdRatio > 0 {
                    thresholdRatio = min(thresholdRatio, requirement.thresholdRatio)
                }
                if requirement.thresholdDelta > 0 {
                    thresholdDelta = min(thresholdDelta, requirement.thresholdDelta)
                }
            }
        }

        if !shouldRequireVisibleChange {
            return VisualVerificationResult(
                actionType: batchActionType,
                required: false,
                changed: false,
                confirmed: true,
                changeRatio: 0,
                averageDelta: 0,
                thresholdRatio: thresholdRatio,
                thresholdDelta: thresholdDelta,
                reason: "No visible change is required for \(batchActionType).",
            )
        }

        let metrics = try compareScreens(before: before, after: after)
        let changed = metrics.changeRatio >= thresholdRatio || metrics.averageDelta >= thresholdDelta
        let reason = changed
            ? "Visible screen change confirmed after \(batchActionType)."
            : "No meaningful visible screen change was detected after \(batchActionType)."
        return VisualVerificationResult(
            actionType: batchActionType,
            required: true,
            changed: changed,
            confirmed: changed,
            changeRatio: metrics.changeRatio,
            averageDelta: metrics.averageDelta,
            thresholdRatio: thresholdRatio,
            thresholdDelta: thresholdDelta,
            reason: reason,
        )
    }

    private func verifyVisualOutcome(actionType: String, action: [String: JSONValue], goal: String?, before: CGImage, after: CGImage) throws -> VisualVerificationResult {
        let requirement = verificationRequirement(for: actionType)
        let shouldRequireVisibleChange = requirement.requiredByDefault || goalRequiresVisibleChange(actionType: actionType, action: action, goal: goal)
        let thresholdRatio = requirement.thresholdRatio
        let thresholdDelta = requirement.thresholdDelta
        if !shouldRequireVisibleChange {
            return VisualVerificationResult(
                actionType: actionType,
                required: false,
                changed: false,
                confirmed: true,
                changeRatio: 0,
                averageDelta: 0,
                thresholdRatio: thresholdRatio,
                thresholdDelta: thresholdDelta,
                reason: "No visible change is required for \(actionType).",
            )
        }

        let metrics = try compareScreens(before: before, after: after)
        let changed = metrics.changeRatio >= thresholdRatio || metrics.averageDelta >= thresholdDelta
        let reason = changed
            ? "Visible screen change confirmed after \(actionType)."
            : "No meaningful visible screen change was detected after \(actionType)."
        return VisualVerificationResult(
            actionType: actionType,
            required: true,
            changed: changed,
            confirmed: changed,
            changeRatio: metrics.changeRatio,
            averageDelta: metrics.averageDelta,
            thresholdRatio: thresholdRatio,
            thresholdDelta: thresholdDelta,
            reason: reason,
        )
    }

    private func verificationRequirement(for actionType: String) -> (requiredByDefault: Bool, thresholdRatio: Double, thresholdDelta: Double) {
        switch actionType {
        case "scroll", "drag":
            return (true, 0.012, 0.008)
        case "type":
            return (false, 0.0015, 0.0009)
        case "key_press":
            return (false, 0.0018, 0.0010)
        case "click", "double_click":
            return (false, 0.0022, 0.0012)
        default:
            return (false, 0.0, 0.0)
        }
    }

    private func goalRequiresVisibleChange(actionType: String, action: [String: JSONValue], goal: String?) -> Bool {
        let normalizedGoal = (goal ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedGoal.isEmpty {
            return false
        }

        let noProofNeededGoalTokens = [
            "copy",
            "copier",
            "copiar",
            "read clipboard",
            "lire le presse-papiers",
            "pasteboard",
        ]
        if noProofNeededGoalTokens.contains(where: normalizedGoal.contains) {
            return false
        }

        switch actionType {
        case "type":
            return true
        case "scroll", "drag":
            return true
        case "click", "double_click", "key_press":
            if actionType == "key_press",
               let keys = action["keys"]?.arrayValue?.compactMap(\.stringValue).map({ $0.lowercased() }) {
                let normalizedKeys = Set(keys)
                if normalizedKeys == ["cmd", "c"] || normalizedKeys == ["command", "c"] {
                    return false
                }
            }

            let visibleGoalTokens = [
                "focus",
                "address bar",
                "open",
                "ouvrir",
                "abrir",
                "show",
                "afficher",
                "mostrar",
                "submit",
                "send",
                "load",
                "navigate",
                "go to",
                "search",
                "recherche",
                "buscar",
                "select",
                "selection",
                "select the visible",
                "activate",
                "switch",
                "bring",
                "place the text cursor",
                "cursor",
                "highlight",
                "press enter",
            ]
            return visibleGoalTokens.contains(where: normalizedGoal.contains)
        default:
            return false
        }
    }

    private func compareScreens(before: CGImage, after: CGImage) throws -> (changeRatio: Double, averageDelta: Double) {
        let sampleWidth = 96
        let sampleHeight = 96
        let beforeBuffer = try normalizedPixelBuffer(from: before, width: sampleWidth, height: sampleHeight)
        let afterBuffer = try normalizedPixelBuffer(from: after, width: sampleWidth, height: sampleHeight)
        guard beforeBuffer.count == afterBuffer.count else {
            throw RuntimeProtocolError.runtimeFailure("Unable to compare screen buffers of different sizes.")
        }

        var changedPixels = 0
        var totalDelta = 0.0
        let pixelCount = sampleWidth * sampleHeight
        for index in stride(from: 0, to: beforeBuffer.count, by: 4) {
            let redDelta = abs(Int(beforeBuffer[index]) - Int(afterBuffer[index]))
            let greenDelta = abs(Int(beforeBuffer[index + 1]) - Int(afterBuffer[index + 1]))
            let blueDelta = abs(Int(beforeBuffer[index + 2]) - Int(afterBuffer[index + 2]))
            let normalizedDelta = Double(redDelta + greenDelta + blueDelta) / (255.0 * 3.0)
            totalDelta += normalizedDelta
            if normalizedDelta >= 0.08 {
                changedPixels += 1
            }
        }
        return (
            changeRatio: Double(changedPixels) / Double(pixelCount),
            averageDelta: totalDelta / Double(pixelCount)
        )
    }

    private func normalizedPixelBuffer(from image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let contextCreated = buffer.withUnsafeMutableBytes { rawBuffer -> CGContext? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            return CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }
        guard let context = contextCreated else {
            throw RuntimeProtocolError.runtimeFailure("Unable to create normalized screen comparison context.")
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func screenshotCoordinateToDisplayPoint(x: Double, y: Double) -> CGPoint {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let pixelWidth = Double(CGDisplayPixelsWide(displayID))
        let pixelHeight = Double(CGDisplayPixelsHigh(displayID))

        guard pixelWidth > 0, pixelHeight > 0, bounds.width > 0, bounds.height > 0 else {
            return CGPoint(x: x, y: y)
        }

        let clampedX = min(max(x, 0), pixelWidth)
        let clampedY = min(max(y, 0), pixelHeight)
        return CGPoint(
            x: bounds.origin.x + (clampedX / pixelWidth) * bounds.width,
            y: bounds.origin.y + (clampedY / pixelHeight) * bounds.height
        )
    }

    private func displayRectToScreenshotPixelBounds(x: Double, y: Double, width: Double, height: Double) -> [String: JSONValue] {
        let displayID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(displayID)
        let pixelWidth = Double(CGDisplayPixelsWide(displayID))
        let pixelHeight = Double(CGDisplayPixelsHigh(displayID))

        guard pixelWidth > 0, pixelHeight > 0, displayBounds.width > 0, displayBounds.height > 0 else {
            return [
                "x": .number(x),
                "y": .number(y),
                "width": .number(width),
                "height": .number(height),
            ]
        }

        return [
            "x": .number(((x - displayBounds.origin.x) / displayBounds.width) * pixelWidth),
            "y": .number(((y - displayBounds.origin.y) / displayBounds.height) * pixelHeight),
            "width": .number((width / displayBounds.width) * pixelWidth),
            "height": .number((height / displayBounds.height) * pixelHeight),
        ]
    }

    private func click(at point: CGPoint, button: String, clickCount: Int) throws {
        let mouseButton: CGMouseButton = button.lowercased() == "right" ? .right : .left
        let downType: CGEventType = mouseButton == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = mouseButton == .right ? .rightMouseUp : .leftMouseUp

        try moveMouse(to: point, button: mouseButton)

        for index in 1...clickCount {
            guard
                let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton),
                let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton)
            else {
                throw RuntimeProtocolError.runtimeFailure("Unable to construct mouse click event.")
            }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(80_000)
        }
    }

    private func moveMouse(to point: CGPoint, button: CGMouseButton = .left) throws {
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button) else {
            throw RuntimeProtocolError.runtimeFailure("Unable to construct mouse move event.")
        }
        move.post(tap: .cghidEventTap)
    }

    private func drag(along points: [CGPoint]) throws {
        guard let first = points.first else {
            throw RuntimeProtocolError.invalidParameters("Drag path cannot be empty.")
        }
        try moveMouse(to: first)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: first, mouseButton: .left) else {
            throw RuntimeProtocolError.runtimeFailure("Unable to construct drag mouse down event.")
        }
        down.post(tap: .cghidEventTap)
        usleep(50_000)
        for point in points.dropFirst() {
            guard let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else {
                throw RuntimeProtocolError.runtimeFailure("Unable to construct drag move event.")
            }
            drag.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        let endPoint = points.last ?? first
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: endPoint, mouseButton: .left) else {
            throw RuntimeProtocolError.runtimeFailure("Unable to construct drag mouse up event.")
        }
        up.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) throws {
        for character in text {
            let payload = Array(String(character).utf16)
            guard
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw RuntimeProtocolError.runtimeFailure("Unable to construct keyboard events.")
            }

            down.keyboardSetUnicodeString(stringLength: payload.count, unicodeString: payload)
            up.keyboardSetUnicodeString(stringLength: payload.count, unicodeString: payload)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(8_000)
        }
    }

    private func keyPress(_ keys: [String]) throws {
        guard let keyCode = KeyboardLayout.primaryKeyCode(for: keys) else {
            throw RuntimeProtocolError.invalidParameters("No supported primary key found in keys array.")
        }
        let flags = KeyboardLayout.modifierFlags(for: keys)
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            throw RuntimeProtocolError.runtimeFailure("Unable to construct keyboard combo event.")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func scroll(deltaX: Int32, deltaY: Int32) throws {
        // Codex computer-use deltas use the human/screenshot convention:
        // positive Y means "scroll down". CGEvent wheel deltas use the opposite
        // sign on macOS, so invert here to keep the public MCP contract stable.
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: -deltaY,
            wheel2: -deltaX,
            wheel3: 0
        ) else {
            throw RuntimeProtocolError.runtimeFailure("Unable to construct scroll event.")
        }
        event.post(tap: .cghidEventTap)
    }

    private func listWindows() -> JSONValue {
        .object(["windows": .array(visibleWindows().map(windowPayload(from:)))])
    }

    private func visibleWindowEntries() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private func visibleWindows() -> [[String: Any]] {
        visibleWindowEntries().filter { entry in
            guard
                let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                let width = bounds["Width"] as? Double,
                let height = bounds["Height"] as? Double
            else {
                return false
            }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            return alpha > 0 && width > 0 && height > 0 && layer >= 0
        }
    }

    private func windowPayload(from entry: [String: Any]) -> JSONValue {
        let bounds = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let x = bounds["X"] as? Double ?? 0
        let y = bounds["Y"] as? Double ?? 0
        let width = bounds["Width"] as? Double ?? 0
        let height = bounds["Height"] as? Double ?? 0
        let layer = entry[kCGWindowLayer as String] as? Int ?? 0
        let screenshotBounds = displayRectToScreenshotPixelBounds(x: x, y: y, width: width, height: height)
        return .object([
            "window_id": .number(Double(entry[kCGWindowNumber as String] as? Int ?? 0)),
            "owner_name": .string(entry[kCGWindowOwnerName as String] as? String ?? ""),
            "window_name": .string(entry[kCGWindowName as String] as? String ?? ""),
            "bounds": .object(screenshotBounds),
            "bounds_units": .string("screenshot_image_pixels"),
            "display_bounds": .object([
                "x": .number(x),
                "y": .number(y),
                "width": .number(width),
                "height": .number(height),
            ]),
            "display_bounds_units": .string("macos_display_points"),
            "layer": .number(Double(layer)),
            "pid": .number(Double(entry[kCGWindowOwnerPID as String] as? Int ?? 0)),
        ])
    }

    private func focusApplication(arguments: [String: JSONValue]) throws {
        let bundleIdentifier = arguments["bundle_id"]?.stringValue
        let name = arguments["name"]?.stringValue

        let app: NSRunningApplication?
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        } else if let name, !name.isEmpty {
            let lowered = name.lowercased()
            app = NSWorkspace.shared.runningApplications.first {
                ($0.localizedName ?? "").lowercased() == lowered
            }
        } else {
            throw RuntimeProtocolError.invalidParameters("desktop_focus_application requires name or bundle_id")
        }

        guard let app else {
            throw RuntimeProtocolError.runtimeFailure("Application is not running.")
        }

        let activated = try runOnMain {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        guard activated else {
            throw RuntimeProtocolError.runtimeFailure("Application activation was rejected by macOS.")
        }
    }

    private func focusWindow(arguments: [String: JSONValue]) throws -> [String: JSONValue] {
        try ensureAccessibility()

        let titleQuery = (
            arguments["title"]?.stringValue
            ?? arguments["query"]?.stringValue
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerQuery = (arguments["owner_name"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = (arguments["bundle_id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !titleQuery.isEmpty || !ownerQuery.isEmpty || !bundleIdentifier.isEmpty else {
            throw RuntimeProtocolError.invalidParameters("desktop_focus_window requires title, query, owner_name, or bundle_id")
        }

        let candidate = try resolveWindowCandidate(
            titleQuery: titleQuery,
            ownerQuery: ownerQuery,
            bundleIdentifier: bundleIdentifier
        )

        let app = NSRunningApplication(processIdentifier: pid_t(candidate.pid))
        guard let app else {
            throw RuntimeProtocolError.runtimeFailure("Unable to resolve running app for pid \(candidate.pid).")
        }

        let activated = try runOnMain {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        guard activated else {
            throw RuntimeProtocolError.runtimeFailure("Application activation was rejected by macOS.")
        }

        let appElement = AXUIElementCreateApplication(pid_t(candidate.pid))
        let focusedByAX = focusAXWindow(
            appElement: appElement,
            titleQuery: titleQuery,
            fallbackTitle: candidate.windowName
        )

        return [
            "window_id": .number(Double(candidate.windowID)),
            "owner_name": .string(candidate.ownerName),
            "window_name": .string(candidate.windowName),
            "pid": .number(Double(candidate.pid)),
            "focused_via_accessibility": .bool(focusedByAX),
        ]
    }

    private func resolveWindowCandidate(titleQuery: String, ownerQuery: String, bundleIdentifier: String) throws -> (windowID: Int, pid: Int, ownerName: String, windowName: String) {
        let allowedPIDs: Set<Int>? = bundleIdentifier.isEmpty ? nil : Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map { Int($0.processIdentifier) }
        )
        if bundleIdentifier.isEmpty == false, allowedPIDs?.isEmpty == true {
            throw RuntimeProtocolError.runtimeFailure("No running app matches bundle id \(bundleIdentifier).")
        }

        let titleNeedle = titleQuery.lowercased()
        let ownerNeedle = ownerQuery.lowercased()
        let windows = visibleWindows()

        var bestMatch: (score: Int, entry: [String: Any])?
        for entry in windows {
            let pid = entry[kCGWindowOwnerPID as String] as? Int ?? 0
            if let allowedPIDs, allowedPIDs.contains(pid) == false {
                continue
            }

            let ownerName = (entry[kCGWindowOwnerName as String] as? String ?? "")
            let windowName = (entry[kCGWindowName as String] as? String ?? "")
            let ownerLower = ownerName.lowercased()
            let windowLower = windowName.lowercased()

            var score = 0
            if titleNeedle.isEmpty == false {
                if windowLower == titleNeedle {
                    score += 8
                } else if windowLower.contains(titleNeedle) {
                    score += 5
                } else {
                    continue
                }
            }

            if ownerNeedle.isEmpty == false {
                if ownerLower == ownerNeedle {
                    score += 4
                } else if ownerLower.contains(ownerNeedle) {
                    score += 2
                } else {
                    continue
                }
            }

            if titleNeedle.isEmpty && ownerNeedle.isEmpty && allowedPIDs != nil {
                score += 1
            }

            if bestMatch == nil || score > bestMatch?.score ?? Int.min {
                bestMatch = (score, entry)
            }
        }

        guard let entry = bestMatch?.entry else {
            throw RuntimeProtocolError.runtimeFailure("No visible window matched the requested title/app query.")
        }

        return (
            windowID: entry[kCGWindowNumber as String] as? Int ?? 0,
            pid: entry[kCGWindowOwnerPID as String] as? Int ?? 0,
            ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
            windowName: entry[kCGWindowName as String] as? String ?? ""
        )
    }

    private func focusAXWindow(appElement: AXUIElement, titleQuery: String, fallbackTitle: String) -> Bool {
        let windows = axWindows(for: appElement)
        if windows.isEmpty {
            return false
        }

        let desired = titleQuery.isEmpty ? fallbackTitle.lowercased() : titleQuery.lowercased()
        let target = windows.first { window in
            guard desired.isEmpty == false else { return true }
            let title = axString(for: window, attribute: kAXTitleAttribute as CFString).lowercased()
            return title == desired || title.contains(desired)
        } ?? windows.first

        guard let target else {
            return false
        }

        var focused = false
        let raiseResult = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        focused = focused || raiseResult == .success
        let mainResult = AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        focused = focused || mainResult == .success
        let focusResult = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        focused = focused || focusResult == .success
        let focusedWindowResult = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
        focused = focused || focusedWindowResult == .success
        return focused
    }

    private func axWindows(for appElement: AXUIElement) -> [AXUIElement] {
        guard let value = axValue(for: appElement, attribute: kAXWindowsAttribute as CFString) else {
            return []
        }
        if let windows = value as? [AXUIElement] {
            return windows
        }
        if let array = value as? [Any] {
            return array.map { $0 as! AXUIElement }
        }
        return []
    }

    private func axString(for element: AXUIElement, attribute: CFString) -> String {
        (axValue(for: element, attribute: attribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func axValue(for element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func openApplication(arguments: [String: JSONValue]) throws -> String {
        final class CompletionBox: @unchecked Sendable {
            var error: Error?
        }

        let path = arguments["path"]?.stringValue
        let bundleIdentifier = arguments["bundle_id"]?.stringValue
        let name = arguments["name"]?.stringValue

        let appURL: URL
        let descriptor: String

        if let path, !path.isEmpty {
            appURL = URL(fileURLWithPath: path)
            descriptor = path
        } else if let bundleIdentifier, !bundleIdentifier.isEmpty {
            guard let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw RuntimeProtocolError.runtimeFailure("Unable to resolve app for bundle id \(bundleIdentifier).")
            }
            appURL = resolved
            descriptor = bundleIdentifier
        } else if let name, !name.isEmpty {
            guard let resolved = resolveApplicationURL(named: name) else {
                throw RuntimeProtocolError.runtimeFailure("Unable to resolve app named \(name).")
            }
            appURL = resolved
            descriptor = name
        } else {
            throw RuntimeProtocolError.invalidParameters("system_open_application requires path, bundle_id, or name")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        let completion = CompletionBox()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            completion.error = error
            semaphore.signal()
        }
        semaphore.wait()
        if let completionError = completion.error {
            throw completionError
        }

        return descriptor
    }

    private func resolveApplicationURL(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let appName = trimmed.lowercased().hasSuffix(".app") ? trimmed : "\(trimmed).app"

        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").caseInsensitiveCompare(trimmed) == .orderedSame
        }), let bundleURL = running.bundleURL {
            return bundleURL
        }

        let candidateRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Applications", isDirectory: true),
        ]

        for root in candidateRoots {
            let directCandidate = root.appendingPathComponent(appName, isDirectory: true)
            if FileManager.default.fileExists(atPath: directCandidate.path) {
                return directCandidate
            }
        }

        for root in candidateRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                if url.lastPathComponent.caseInsensitiveCompare(appName) == .orderedSame {
                    return url
                }
            }
        }

        return nil
    }

    private func openURL(_ rawURL: String) throws {
        guard let url = URL(string: rawURL), let scheme = url.scheme, ["http", "https", "file"].contains(scheme.lowercased()) else {
            throw RuntimeProtocolError.invalidParameters("system_open_url requires a valid http, https, or file URL")
        }
        let opened = try runOnMain {
            NSWorkspace.shared.open(url)
        }
        guard opened else {
            throw RuntimeProtocolError.runtimeFailure("macOS refused to open \(rawURL).")
        }
    }

    private func revealPath(_ rawPath: String) throws {
        let url = URL(fileURLWithPath: rawPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeProtocolError.runtimeFailure("Path does not exist: \(rawPath)")
        }
        try runOnMain {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func readClipboard() throws -> JSONValue {
        let text = try runOnMain {
            NSPasteboard.general.string(forType: .string)
        } ?? ""
        return .object([
            "text": .string(text),
            "length": .number(Double(text.count)),
        ])
    }

    private func readClipboardImage() throws -> JSONValue {
        let payload = try runOnMain { () throws -> [String: JSONValue] in
            let pasteboard = NSPasteboard.general

            if let pngData = pasteboard.data(forType: .png) {
                return try self.clipboardImagePayload(data: pngData, fallbackMime: "image/png")
            }

            if let tiffData = pasteboard.data(forType: .tiff) {
                return try self.clipboardImagePayload(data: tiffData, fallbackMime: "image/tiff")
            }

            if
                let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
                let pngData = try? self.pngData(from: image)
            {
                return try self.clipboardImagePayload(data: pngData, fallbackMime: "image/png")
            }

            throw RuntimeProtocolError.runtimeFailure("Clipboard does not contain an image.")
        }

        return .object(payload)
    }

    private func writeClipboard(_ text: String) throws {
        try runOnMain {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    private func pasteClipboard() throws {
        try ensureAccessibility()
        try keyPress(["command", "v"])
    }

    private func selectFileForActiveDialog(_ rawPath: String) throws -> [String: JSONValue] {
        try ensureAccessibility()
        let normalizedPath = try normalizedExistingPath(rawPath)

        try keyPress(["command", "shift", "g"])
        usleep(220_000)
        try keyPress(["command", "a"])
        usleep(80_000)
        try typeText(normalizedPath)
        usleep(120_000)
        try keyPress(["return"])

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue == false {
            usleep(220_000)
            try keyPress(["return"])
        }

        return [
            "path": .string(normalizedPath),
            "is_directory": .bool(isDirectory.boolValue),
        ]
    }

    private func normalizedExistingPath(_ rawPath: String) throws -> String {
        let expanded = NSString(string: rawPath).expandingTildeInPath
        let standardized = NSString(string: expanded).standardizingPath
        guard FileManager.default.fileExists(atPath: standardized) else {
            throw RuntimeProtocolError.runtimeFailure("Path does not exist: \(standardized)")
        }
        return standardized
    }

    private func clipboardImagePayload(data: Data, fallbackMime: String) throws -> [String: JSONValue] {
        let imageData: Data
        let mimeType: String
        let width: Double
        let height: Double

        if let bitmap = NSBitmapImageRep(data: data) {
            width = Double(bitmap.pixelsWide)
            height = Double(bitmap.pixelsHigh)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                imageData = pngData
                mimeType = "image/png"
            } else {
                imageData = data
                mimeType = fallbackMime
            }
        } else if let image = NSImage(data: data) {
            imageData = try pngData(from: image)
            width = Double(max(1, Int(image.size.width.rounded())))
            height = Double(max(1, Int(image.size.height.rounded())))
            mimeType = "image/png"
        } else {
            throw RuntimeProtocolError.runtimeFailure("Clipboard image data could not be decoded.")
        }

        return [
            "mime": .string(mimeType),
            "image_base64": .string(imageData.base64EncodedString()),
            "width": .number(width),
            "height": .number(height),
            "size_bytes": .number(Double(imageData.count)),
        ]
    }

    private func pngData(from image: NSImage) throws -> Data {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw RuntimeProtocolError.runtimeFailure("Unable to encode clipboard image as PNG.")
        }
        return pngData
    }

    private func runOnMain<T>(_ block: @escaping @Sendable () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try block()
        }
        return try DispatchQueue.main.sync(execute: block)
    }
}
