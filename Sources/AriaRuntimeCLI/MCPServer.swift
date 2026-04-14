import Foundation
import Darwin
import AriaRuntimeMacOS
import AriaRuntimeShared

private struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

private struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONValue?
}

private enum MCPFrameEncoding {
    case contentLength
    case jsonLines
}

private final class AriaSessionState {
    private(set) var bootstrapCount = 0
    private(set) var snapshotCount = 0
    private(set) var actionCount = 0
    private(set) var activeTask = ""
    private(set) var lastTool = ""
    private(set) var screenObservationReady = false

    func registerBootstrap(task: String?) {
        bootstrapCount += 1
        snapshotCount = 0
        actionCount = 0
        screenObservationReady = false
        activeTask = task?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lastTool = "aria_bootstrap"
    }

    func markNavigation(tool: String) {
        screenObservationReady = false
        lastTool = tool
    }

    func markSnapshot() {
        snapshotCount += 1
        screenObservationReady = true
        lastTool = "computer_snapshot"
    }

    func markAction() {
        actionCount += 1
        screenObservationReady = true
        lastTool = "computer_action"
    }

    func statusPayload() -> JSONValue {
        .object([
            "bootstrap_count": .number(Double(bootstrapCount)),
            "snapshot_count": .number(Double(snapshotCount)),
            "action_count": .number(Double(actionCount)),
            "active_task": .string(activeTask),
            "last_tool": .string(lastTool),
            "screen_observation_ready": .bool(screenObservationReady),
        ])
    }
}

final class MCPServer {
    private let service = MacOSRuntimeService()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder.runtimeEncoder()
    private let delimiters = [Data("\r\n\r\n".utf8), Data("\n\n".utf8)]
    private var inputBuffer = Data()
    private let sessionState = AriaSessionState()
    private let traceEnabled = ProcessInfo.processInfo.environment["ARIA_MCP_TRACE"] == "1"

    func run() throws {
        trace("server_start version=\(service.version)")
        while let message = try readFrame() {
            if message.payload.isEmpty {
                trace("server_eof")
                return
            }
            trace("frame_received bytes=\(message.payload.count)")
            let request = try decoder.decode(JSONRPCRequest.self, from: message.payload)
            trace("request method=\(request.method)")
            if let response = handle(request) {
                try writeFrame(response, encoding: message.encoding)
            }
        }
    }

    private func handle(_ request: JSONRPCRequest) -> JSONRPCResponse? {
        switch request.method {
        case "initialize":
            let version = request.params?.objectValue?["protocolVersion"]?.stringValue ?? "2025-03-26"
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object([
                    "protocolVersion": .string(version),
                    "capabilities": .object([
                        "prompts": .object([
                            "listChanged": .bool(false),
                        ]),
                        "resources": .object([
                            "subscribe": .bool(false),
                            "listChanged": .bool(false),
                        ]),
                        "tools": .object([
                            "listChanged": .bool(false),
                        ]),
                    ]),
                    "instructions": .string(AriaControlPlane.initializeInstructions),
                    "serverInfo": .object([
                        "name": .string("aria-runtime"),
                        "version": .string(service.version),
                    ]),
                ]),
                error: nil
            )
        case "notifications/initialized":
            return nil
        case "ping":
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: .object([:]), error: nil)
        case "tools/list":
            let tools = service.toolDescriptors().map { tool in
                JSONValue.object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            }
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object(["tools": .array(tools)]),
                error: nil
            )
        case "resources/list":
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object(["resources": .array(resourceList())]),
                error: nil
            )
        case "resources/read":
            guard let requestID = request.id else {
                return jsonRPCError(id: nil, code: -32600, message: "resources/read requires an id")
            }
            guard
                let params = request.params?.objectValue,
                let uri = params["uri"]?.stringValue
            else {
                return jsonRPCError(id: requestID, code: -32602, message: "Missing resource uri")
            }
            guard let content = resourceContents(for: uri) else {
                return jsonRPCError(id: requestID, code: -32602, message: "Unknown resource uri: \(uri)")
            }
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: requestID,
                result: .object(["contents": .array([content])]),
                error: nil
            )
        case "resources/templates/list":
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object(["resourceTemplates": .array([])]),
                error: nil
            )
        case "prompts/list":
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object(["prompts": .array(promptList())]),
                error: nil
            )
        case "prompts/get":
            guard let requestID = request.id else {
                return jsonRPCError(id: nil, code: -32600, message: "prompts/get requires an id")
            }
            guard
                let params = request.params?.objectValue,
                let name = params["name"]?.stringValue
            else {
                return jsonRPCError(id: requestID, code: -32602, message: "Missing prompt name")
            }
            guard let prompt = prompt(named: name, arguments: params["arguments"]?.objectValue ?? [:]) else {
                return jsonRPCError(id: requestID, code: -32602, message: "Unknown prompt name: \(name)")
            }
            return JSONRPCResponse(jsonrpc: "2.0", id: requestID, result: prompt, error: nil)
        case "tools/call":
            guard let requestID = request.id else {
                return jsonRPCError(id: nil, code: -32600, message: "tools/call requires an id")
            }
            guard
                let params = request.params?.objectValue,
                let toolName = params["name"]?.stringValue
            else {
                return jsonRPCError(id: requestID, code: -32602, message: "Missing tool name")
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            if let violation = policyViolation(toolName: toolName, arguments: arguments) {
                let payload: JSONValue = .object([
                    "error": .object([
                        "code": .string("aria_policy_violation"),
                        "message": .string(violation),
                    ]),
                    "session": sessionState.statusPayload(),
                ])
                return JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: requestID,
                    result: .object([
                        "content": .array(buildToolContent(payload)),
                        "isError": .bool(true),
                        "structuredContent": payload,
                    ]),
                    error: nil
                )
            }
            let runtimeResponse = service.handle(
                RuntimeRequest(
                    method: .invoke,
                    params: .object([
                        "tool": .string(toolName),
                        "arguments": .object(arguments),
                    ])
                )
            )

            let structuredContent: JSONValue
            if runtimeResponse.ok {
                structuredContent = augmentSuccessfulResult(
                    toolName: toolName,
                    arguments: arguments,
                    result: runtimeResponse.result ?? .object([:])
                )
            } else {
                structuredContent = .object([
                    "error": .object([
                        "code": .string(runtimeResponse.error?.code ?? "runtime_error"),
                        "message": .string(runtimeResponse.error?.message ?? "Unknown runtime error"),
                    ]),
                ])
            }
            let toolError = shouldMarkToolError(toolName: toolName, runtimeResponseOK: runtimeResponse.ok, structuredContent: structuredContent)

            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: requestID,
                result: .object([
                    "content": .array(buildToolContent(structuredContent)),
                    "isError": .bool(toolError),
                    "structuredContent": structuredContent,
                ]),
                error: nil
            )
        default:
            guard let requestID = request.id else {
                return nil
            }
            return jsonRPCError(id: requestID, code: -32601, message: "Method not found: \(request.method)")
        }
    }

    private func jsonRPCError(id: JSONValue?, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: nil,
            error: .object([
                "code": .number(Double(code)),
                "message": .string(message),
            ])
        )
    }

    private func renderJSON(_ value: JSONValue) -> String {
        do {
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return #"{"error":"encoding_failed"}"#
        }
    }

    private func shouldMarkToolError(toolName: String, runtimeResponseOK: Bool, structuredContent: JSONValue) -> Bool {
        if !runtimeResponseOK {
            return true
        }
        guard toolName == "computer_action", let object = structuredContent.objectValue else {
            return false
        }
        return object["ok"]?.boolValue == false
    }

    private func policyViolation(toolName: String, arguments: [String: JSONValue]) -> String? {
        if sessionState.bootstrapCount > 0 {
            let allowedDuringVisualTask: Set<String> = [
                "runtime_health",
                "runtime_permissions",
                "aria_bootstrap",
                "system_open_application",
                "system_open_url",
                "computer_snapshot",
                "computer_action",
            ]

            if !allowedDuringVisualTask.contains(toolName) {
                return "After aria_bootstrap, this visual task is locked to Aria's canonical loop only: system_open_application or system_open_url for entry/navigation, then computer_snapshot and computer_action. Do not use \(toolName) for this visual task."
            }
        }

        switch toolName {
        case "aria_bootstrap", "runtime_health", "runtime_permissions":
            return nil
        case "system_open_application", "system_open_url":
            guard sessionState.bootstrapCount > 0 else {
                return "Call aria_bootstrap before using navigation tools so Codex enters the Aria control loop."
            }
            return nil
        case "computer_snapshot":
            guard sessionState.bootstrapCount > 0 else {
                return "Call aria_bootstrap before the first computer_snapshot."
            }
            return nil
        case "computer_action":
            guard sessionState.bootstrapCount > 0 else {
                return "Call aria_bootstrap before the first computer_action."
            }
            guard sessionState.screenObservationReady else {
                return "Call computer_snapshot after aria_bootstrap and after every navigation step before computer_action."
            }
            guard arguments["action"]?.objectValue != nil else {
                return nil
            }
            return nil
        case "desktop_list_windows", "desktop_focus_application", "desktop_focus_window", "read_clipboard", "read_clipboard_image", "copy_to_clipboard", "paste", "select_file_for_active_dialog", "upload_file_to_active_app", "reveal_path":
            return "This tool is not allowed inside Aria's locked visual loop. Use system_open_application or system_open_url to enter, then use computer_snapshot and computer_action one step at a time."
        default:
            return nil
        }
    }

    private func augmentSuccessfulResult(toolName: String, arguments: [String: JSONValue], result: JSONValue) -> JSONValue {
        switch toolName {
        case "aria_bootstrap":
            sessionState.registerBootstrap(task: arguments["task"]?.stringValue)
        case "system_open_application", "system_open_url":
            sessionState.markNavigation(tool: toolName)
        case "computer_snapshot":
            sessionState.markSnapshot()
        case "computer_action":
            sessionState.markAction()
        default:
            break
        }

        guard var object = result.objectValue else {
            return result
        }
        object["session"] = sessionState.statusPayload()
        if toolName == "aria_bootstrap" {
            object["next_required_tool"] = .string("computer_snapshot")
        } else if toolName == "system_open_application"
            || toolName == "system_open_url" {
            object["next_required_tool"] = .string("computer_snapshot")
        }
        return .object(object)
    }

    private func resourceList() -> [JSONValue] {
        [
            .object([
                "uri": .string("aria://policy/computer-use"),
                "name": .string("aria-policy-computer-use"),
                "title": .string("Aria Computer Use Policy"),
                "description": .string("Mandatory Aria rules that constrain Codex during visual tasks."),
                "mimeType": .string("text/plain"),
            ]),
            .object([
                "uri": .string("aria://workflow/visual-loop"),
                "name": .string("aria-workflow-visual-loop"),
                "title": .string("Aria Visual Loop"),
                "description": .string("Canonical snapshot -> single action -> snapshot workflow."),
                "mimeType": .string("text/plain"),
            ]),
            .object([
                "uri": .string("aria://product/install-surface"),
                "name": .string("aria-product-install-surface"),
                "title": .string("Aria Install Surface"),
                "description": .string("Explains that end users receive packaged binaries, not the full source repository."),
                "mimeType": .string("text/plain"),
            ]),
        ]
    }

    private func resourceContents(for uri: String) -> JSONValue? {
        let text: String
        switch uri {
        case "aria://policy/computer-use":
            text = AriaControlPlane.policyResourceText()
        case "aria://workflow/visual-loop":
            text = AriaControlPlane.workflowResourceText()
        case "aria://product/install-surface":
            text = AriaControlPlane.installResourceText()
        default:
            return nil
        }

        return .object([
            "uri": .string(uri),
            "mimeType": .string("text/plain"),
            "text": .string(text),
        ])
    }

    private func promptList() -> [JSONValue] {
        [
            .object([
                "name": .string("aria_computer_use"),
                "title": .string("Aria Computer Use"),
                "description": .string("Inject Aria's control loop into Codex before a visual task."),
                "arguments": .array([
                    .object([
                        "name": .string("task"),
                        "description": .string("Optional current user goal for the visual task."),
                        "required": .bool(false),
                    ]),
                ]),
            ]),
        ]
    }

    private func prompt(named name: String, arguments: [String: JSONValue]) -> JSONValue? {
        guard name == "aria_computer_use" else {
            return nil
        }
        let text = AriaControlPlane.promptText(task: arguments["task"]?.stringValue)
        return .object([
            "description": .string("Aria control prompt for Codex-driven computer use."),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string(text),
                    ]),
                ]),
            ]),
        ])
    }

    private func buildToolContent(_ structuredContent: JSONValue) -> [JSONValue] {
        var content: [JSONValue] = [
            .object([
                "type": .string("text"),
                "text": .string(renderJSON(sanitizedTextContent(from: structuredContent))),
            ]),
        ]
        if let imageContent = screenshotImageContent(from: structuredContent) {
            content.append(imageContent)
        }
        return content
    }

    private func screenshotImageContent(from value: JSONValue) -> JSONValue? {
        guard
            let object = value.objectValue,
            let mimeType = object["mime"]?.stringValue,
            let data = object["image_base64"]?.stringValue,
            mimeType.hasPrefix("image/"),
            !data.isEmpty
        else {
            return nil
        }
        return .object([
            "type": .string("image"),
            "data": .string(data),
            "mimeType": .string(mimeType),
        ])
    }

    private func sanitizedTextContent(from value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var sanitized: [String: JSONValue] = [:]
            for (key, child) in object {
                if key == "image_base64" {
                    sanitized[key] = .string("<omitted; see image content>")
                } else {
                    sanitized[key] = sanitizedTextContent(from: child)
                }
            }
            return .object(sanitized)
        case .array(let items):
            return .array(items.map { sanitizedTextContent(from: $0) })
        default:
            return value
        }
    }

    private func readFrame() throws -> (payload: Data, encoding: MCPFrameEncoding)? {
        while true {
            if let match = findHeaderDelimiter() {
                let headerRange = match.range
                let delimiterLength = match.delimiterLength
                let headerData = inputBuffer.subdata(in: 0..<headerRange.lowerBound)
                let contentLength = try parseContentLength(headerData)
                let bodyStart = headerRange.lowerBound + delimiterLength
                let available = inputBuffer.count - bodyStart
                if available >= contentLength {
                    trace("frame_ready content_length=\(contentLength)")
                    let frame = inputBuffer.subdata(in: bodyStart..<(bodyStart + contentLength))
                    inputBuffer.removeSubrange(0..<(bodyStart + contentLength))
                    return (frame, .contentLength)
                }
            }

            if let newlineIndex = inputBuffer.firstIndex(of: 0x0A) {
                let line = inputBuffer.subdata(in: 0..<newlineIndex)
                let trimmed = String(data: line, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    trace("frame_ready jsonl bytes=\(line.count)")
                    inputBuffer.removeSubrange(0...newlineIndex)
                    return (Data(trimmed.utf8), .jsonLines)
                }
            }

            var chunk = [UInt8](repeating: 0, count: 4096)
            let readCount = Darwin.read(FileHandle.standardInput.fileDescriptor, &chunk, chunk.count)
            if readCount == 0 {
                trace("stdin_eof")
                if inputBuffer.isEmpty {
                    return nil
                }
                let trailing = inputBuffer
                inputBuffer.removeAll(keepingCapacity: false)
                return (trailing, .jsonLines)
            }
            if readCount < 0 {
                if errno == EINTR {
                    continue
                }
                trace("stdin_error errno=\(errno)")
                throw RuntimeProtocolError.runtimeFailure("Failed reading MCP input: \(String(cString: strerror(errno)))")
            }
            let chunkData = Data(chunk.prefix(readCount))
            trace("stdin_chunk bytes=\(readCount) preview=\(renderPreview(chunkData))")
            inputBuffer.append(chunk, count: readCount)
        }
    }

    private func findHeaderDelimiter() -> (range: Range<Int>, delimiterLength: Int)? {
        for delimiter in delimiters {
            if let range = inputBuffer.range(of: delimiter) {
                return (range, delimiter.count)
            }
        }
        return nil
    }

    private func parseContentLength(_ headerData: Data) throws -> Int {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw RuntimeProtocolError.runtimeFailure("Invalid MCP header encoding")
        }
        for rawLine in headerString.components(separatedBy: "\r\n") {
            let parts = rawLine.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name == "content-length",
               let length = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                return length
            }
        }
        throw RuntimeProtocolError.runtimeFailure("Missing Content-Length header")
    }

    private func writeFrame(_ response: JSONRPCResponse, encoding: MCPFrameEncoding) throws {
        let payload = try encoder.encode(response)
        let headers = "Content-Length: \(payload.count)\r\nContent-Type: application/json\r\n\r\n"
        trace("response id=\(response.id?.stringValue ?? response.id?.intValue.map(String.init) ?? "null") bytes=\(payload.count)")
        switch encoding {
        case .contentLength:
            try write(Data(headers.utf8))
            try write(payload)
        case .jsonLines:
            try write(payload)
            try write(Data("\n".utf8))
        }
    }

    private func write(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw RuntimeProtocolError.runtimeFailure("Missing output bytes")
            }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(FileHandle.standardOutput.fileDescriptor, baseAddress.advanced(by: offset), remaining)
                if written < 0 {
                    throw RuntimeProtocolError.runtimeFailure("Failed writing MCP output: \(String(cString: strerror(errno)))")
                }
                remaining -= written
                offset += written
            }
        }
    }

    private func trace(_ message: String) {
        guard traceEnabled else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/aria-runtime-mcp-trace.log")
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func renderPreview(_ data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            let trimmed = String(string.prefix(300))
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\n", with: "\\n")
            return trimmed
        }
        return data.prefix(120).map { String(format: "%02x", $0) }.joined()
    }
}
