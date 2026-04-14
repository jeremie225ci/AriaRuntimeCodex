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
                description: "Call exactly once at the start of each visual/UI task. Returns Aria's mandatory operating rules for Codex.",
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
                description: "Capture the current screen and return the image plus Aria loop guidance. Requires aria_bootstrap first. Use before the first UI action and after app/site entry.",
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
                description: "The canonical Aria UI tool. Execute exactly one UI action and receive the post-action screenshot to inspect before the next action. Requires aria_bootstrap and a fresh computer_snapshot first.",
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
                        "goal": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            ),
            ToolDescriptor(
                name: "system_open_application",
                description: "Launch an application by name, bundle identifier, or full path. Requires aria_bootstrap first. After opening, call computer_snapshot before acting visually.",
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
                description: "Open a URL using the user's default browser. Requires aria_bootstrap first. After navigation, call computer_snapshot before any visual interaction.",
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
                name: "read_clipboard",
                description: "Read the current macOS text clipboard.",
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
        case "read_clipboard":
            return try readClipboard()
        case "copy_to_clipboard":
            let text = try requiredString(arguments, key: "text")
            try writeClipboard(text)
            return .object([
                "ok": .bool(true),
                "length": .number(Double(text.count)),
            ])
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
        payload["visual_loop_rules"] = .array(AriaControlPlane.visualLoopRules.map(JSONValue.string))
        payload["forbidden_defaults"] = .array(AriaControlPlane.forbiddenDefaults.map(JSONValue.string))
        payload["sensitive_action_rules"] = .array(AriaControlPlane.sensitiveActionRules.map(JSONValue.string))
        payload["next_step"] = .string("Inspect the screenshot, then choose exactly one computer_action.")
        if let goal, !goal.isEmpty {
            payload["goal"] = .string(goal)
        }
        return .object(payload)
    }

    private func computerAction(arguments: [String: JSONValue]) throws -> JSONValue {
        let action = try requiredObject(arguments, key: "action")
        let actionType = try requiredString(action, key: "type")
        let beforeFrame = try captureScreen()
        let executedAction = try executeComputerAction(action)
        settleAfterAction(actionType)
        let afterFrame = try captureScreen()
        let verification = try verifyVisualOutcome(
            actionType: actionType,
            before: beforeFrame.image,
            after: afterFrame.image
        )
        var payload = screenshotPayload(from: afterFrame)
        payload["mode"] = .string("computer_action")
        payload["ok"] = .bool(verification.confirmed || !verification.required)
        payload["executed_action"] = .object(executedAction)
        payload["visual_confirmation"] = verification.payload()
        if let goal = arguments["goal"]?.stringValue, !goal.isEmpty {
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
        ]
    }

    private func executeComputerAction(_ action: [String: JSONValue]) throws -> [String: JSONValue] {
        let actionType = try requiredString(action, key: "type")
        switch actionType {
        case "click":
            let x = try requiredDouble(action, key: "x")
            let y = try requiredDouble(action, key: "y")
            let button = action["button"]?.stringValue ?? "left"
            try ensureAccessibility()
            try click(at: CGPoint(x: x, y: y), button: button, clickCount: 1)
            return [
                "type": .string(actionType),
                "x": .number(x),
                "y": .number(y),
                "button": .string(button),
            ]
        case "double_click":
            let x = try requiredDouble(action, key: "x")
            let y = try requiredDouble(action, key: "y")
            try ensureAccessibility()
            try click(at: CGPoint(x: x, y: y), button: "left", clickCount: 2)
            return [
                "type": .string(actionType),
                "x": .number(x),
                "y": .number(y),
            ]
        case "scroll":
            let deltaX = action["delta_x"]?.doubleValue ?? 0
            let deltaY = action["delta_y"]?.doubleValue ?? 0
            try ensureAccessibility()
            if let x = action["x"]?.doubleValue, let y = action["y"]?.doubleValue {
                try moveMouse(to: CGPoint(x: x, y: y))
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
            try ensureAccessibility()
            try moveMouse(to: CGPoint(x: x, y: y))
            return [
                "type": .string(actionType),
                "x": .number(x),
                "y": .number(y),
            ]
        case "drag":
            guard let path = action["path"]?.arrayValue, !path.isEmpty else {
                throw RuntimeProtocolError.invalidParameters("computer_action drag requires a non-empty path array")
            }
            let points = try path.map { item -> CGPoint in
                guard let point = item.objectValue else {
                    throw RuntimeProtocolError.invalidParameters("computer_action drag path items must be objects")
                }
                return CGPoint(
                    x: try requiredDouble(point, key: "x"),
                    y: try requiredDouble(point, key: "y")
                )
            }
            try ensureAccessibility()
            try drag(along: points)
            return [
                "type": .string(actionType),
                "path": .array(points.map { point in
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

    private func verifyVisualOutcome(actionType: String, before: CGImage, after: CGImage) throws -> VisualVerificationResult {
        let requirement = verificationRequirement(for: actionType)
        if !requirement.required {
            return VisualVerificationResult(
                actionType: actionType,
                required: false,
                changed: false,
                confirmed: true,
                changeRatio: 0,
                averageDelta: 0,
                thresholdRatio: requirement.thresholdRatio,
                thresholdDelta: requirement.thresholdDelta,
                reason: "No visible change is required for \(actionType).",
            )
        }

        let metrics = try compareScreens(before: before, after: after)
        let changed = metrics.changeRatio >= requirement.thresholdRatio || metrics.averageDelta >= requirement.thresholdDelta
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
            thresholdRatio: requirement.thresholdRatio,
            thresholdDelta: requirement.thresholdDelta,
            reason: reason,
        )
    }

    private func verificationRequirement(for actionType: String) -> (required: Bool, thresholdRatio: Double, thresholdDelta: Double) {
        switch actionType {
        case "scroll", "drag":
            return (true, 0.012, 0.008)
        default:
            return (false, 0.0, 0.0)
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
        let payload = Array(text.utf16)
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
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            throw RuntimeProtocolError.runtimeFailure("Unable to construct scroll event.")
        }
        event.post(tap: .cghidEventTap)
    }

    private func listWindows() -> JSONValue {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = windowInfo.compactMap { entry -> JSONValue? in
            guard
                let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                let x = bounds["X"] as? Double,
                let y = bounds["Y"] as? Double,
                let width = bounds["Width"] as? Double,
                let height = bounds["Height"] as? Double
            else {
                return nil
            }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            if alpha <= 0 || width <= 0 || height <= 0 || layer < 0 {
                return nil
            }
            return .object([
                "window_id": .number(Double(entry[kCGWindowNumber as String] as? Int ?? 0)),
                "owner_name": .string(entry[kCGWindowOwnerName as String] as? String ?? ""),
                "window_name": .string(entry[kCGWindowName as String] as? String ?? ""),
                "bounds": .object([
                    "x": .number(x),
                    "y": .number(y),
                    "width": .number(width),
                    "height": .number(height),
                ]),
                "layer": .number(Double(layer)),
                "pid": .number(Double(entry[kCGWindowOwnerPID as String] as? Int ?? 0)),
            ])
        }
        return .object(["windows": .array(windows)])
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

    private func writeClipboard(_ text: String) throws {
        try runOnMain {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    private func runOnMain<T>(_ block: @escaping @Sendable () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try block()
        }
        return try DispatchQueue.main.sync(execute: block)
    }
}
