import Foundation
import Darwin
import AriaRuntimeShared

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

private struct MCPJSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

private struct MCPJSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONValue?
}

private final class JSONLMCPProcessClient {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let encoder = JSONEncoder.runtimeEncoder()
    private let decoder = JSONDecoder()
    private var nextID = 1

    init(executableURL: URL) throws {
        process.executableURL = executableURL
        process.arguments = ["mcp", "serve"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    func request(method: String, params: JSONValue? = nil) throws -> MCPJSONRPCResponse {
        let request = MCPJSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(Double(nextID)),
            method: method,
            params: params
        )
        nextID += 1
        try write(request)
        return try readResponse()
    }

    func notify(method: String, params: JSONValue? = nil) throws {
        let request = MCPJSONRPCRequest(jsonrpc: "2.0", id: nil, method: method, params: params)
        try write(request)
    }

    private func write(_ request: MCPJSONRPCRequest) throws {
        let payload = try encoder.encode(request) + Data("\n".utf8)
        try payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw SmokeFailure(description: "Missing bytes while writing JSONL MCP frame")
            }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(stdinPipe.fileHandleForWriting.fileDescriptor, baseAddress.advanced(by: offset), remaining)
                if written < 0 {
                    throw SmokeFailure(description: "Failed writing JSONL MCP frame: \(String(cString: strerror(errno)))")
                }
                remaining -= written
                offset += written
            }
        }
    }

    private func readResponse() throws -> MCPJSONRPCResponse {
        var data = Data()
        while true {
            var byte = [UInt8](repeating: 0, count: 1)
            let readCount = Darwin.read(stdoutPipe.fileHandleForReading.fileDescriptor, &byte, 1)
            if readCount == 0 {
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw SmokeFailure(description: "JSONL MCP process closed unexpectedly. \(stderr)")
            }
            if readCount < 0 {
                if errno == EINTR {
                    continue
                }
                throw SmokeFailure(description: "Failed reading JSONL MCP response: \(String(cString: strerror(errno)))")
            }
            if byte[0] == 0x0A {
                break
            }
            data.append(byte, count: 1)
        }
        return try decoder.decode(MCPJSONRPCResponse.self, from: data)
    }
}

private final class MCPProcessClient {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let encoder = JSONEncoder.runtimeEncoder()
    private let decoder = JSONDecoder()
    private let delimiter = Data("\r\n\r\n".utf8)
    private var inputBuffer = Data()
    private var nextID = 1

    init(executableURL: URL) throws {
        process.executableURL = executableURL
        process.arguments = ["mcp", "serve"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    func request(method: String, params: JSONValue? = nil) throws -> MCPJSONRPCResponse {
        let id = JSONValue.number(Double(nextID))
        nextID += 1
        let request = MCPJSONRPCRequest(jsonrpc: "2.0", id: id, method: method, params: params)
        try writeFrame(request)
        let response = try readResponse()
        if let error = response.error {
            throw SmokeFailure(description: "MCP error for \(method): \(render(error))")
        }
        return response
    }

    func notify(method: String, params: JSONValue? = nil) throws {
        let request = MCPJSONRPCRequest(jsonrpc: "2.0", id: nil, method: method, params: params)
        try writeFrame(request)
    }

    private func writeFrame(_ request: MCPJSONRPCRequest) throws {
        let payload = try encoder.encode(request)
        let headers = "Content-Length: \(payload.count)\r\nContent-Type: application/json\r\n\r\n"
        try write(Data(headers.utf8), to: stdinPipe.fileHandleForWriting)
        try write(payload, to: stdinPipe.fileHandleForWriting)
    }

    private func readResponse() throws -> MCPJSONRPCResponse {
        let frame = try readFrame()
        return try decoder.decode(MCPJSONRPCResponse.self, from: frame)
    }

    private func readFrame() throws -> Data {
        while true {
            if let headerRange = inputBuffer.range(of: delimiter) {
                let headerData = inputBuffer.subdata(in: 0..<headerRange.lowerBound)
                let contentLength = try parseContentLength(headerData)
                let bodyStart = headerRange.upperBound
                let available = inputBuffer.count - bodyStart
                if available >= contentLength {
                    let frame = inputBuffer.subdata(in: bodyStart..<(bodyStart + contentLength))
                    inputBuffer.removeSubrange(0..<(bodyStart + contentLength))
                    return frame
                }
            }

            var chunk = [UInt8](repeating: 0, count: 4096)
            let readCount = Darwin.read(stdoutPipe.fileHandleForReading.fileDescriptor, &chunk, chunk.count)
            if readCount == 0 {
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw SmokeFailure(description: "MCP process closed unexpectedly. \(stderr)")
            }
            if readCount < 0 {
                if errno == EINTR {
                    continue
                }
                throw SmokeFailure(description: "Failed reading MCP response: \(String(cString: strerror(errno)))")
            }
            inputBuffer.append(chunk, count: readCount)
        }
    }

    private func parseContentLength(_ headerData: Data) throws -> Int {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw SmokeFailure(description: "Invalid MCP frame header encoding")
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
        throw SmokeFailure(description: "Missing Content-Length header in MCP response")
    }

    private func write(_ data: Data, to handle: FileHandle) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw SmokeFailure(description: "Missing bytes while writing MCP frame")
            }

            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(handle.fileDescriptor, baseAddress.advanced(by: offset), remaining)
                if written < 0 {
                    throw SmokeFailure(description: "Failed writing MCP frame: \(String(cString: strerror(errno)))")
                }
                remaining -= written
                offset += written
            }
        }
    }

    private func render(_ value: JSONValue) -> String {
        do {
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return #"{"error":"encoding_failed"}"#
        }
    }
}

enum SmokeRunner {
    static func run(args: [String], executablePath: String) throws {
        switch args {
        case ["mcp"]:
            try runMCPSmoke(executablePath: executablePath)
        case ["codex"]:
            try runCodexJSONLSmoke(executablePath: executablePath)
        case ["runtime"]:
            try runRuntimeSmoke()
        case ["all"], []:
            try runRuntimeSmoke()
            print("")
            try runMCPSmoke(executablePath: executablePath)
            print("")
            try runCodexJSONLSmoke(executablePath: executablePath)
        default:
            throw RuntimeProtocolError.invalidParameters("Supported smoke commands: runtime, mcp, codex, all")
        }
    }

    private static func runRuntimeSmoke() throws {
        print("Aria Runtime smoke test")
        let client = RuntimeClient()

        let health = try client.send(method: .health)
        let healthResult = try requireRuntimeResult(health, context: "runtime.health")
        try require(healthResult["service"]?.stringValue == "aria-runtime", "runtime.health returned the expected service name")
        pass("runtime.health responded")

        let permissions = try client.send(method: .permissions)
        let permissionsResult = try requireRuntimeResult(permissions, context: "runtime.permissions")
        pass("runtime.permissions responded")

        let tools = try client.send(method: .tools)
        let toolResult = try requireRuntimeResult(tools, context: "runtime.tools")
        let toolCount = toolResult["tools"]?.arrayValue?.count ?? 0
        try require(toolCount >= 5, "runtime.tools returned at least five tools")
        pass("runtime.tools returned \(toolCount) tools")

        let bootstrap = try client.invoke(tool: "aria_bootstrap")
        let bootstrapResult = try requireRuntimeResult(bootstrap, context: "aria_bootstrap")
        let canonicalTools = bootstrapResult["canonical_visual_tools"]?.arrayValue?.compactMap(\.stringValue) ?? []
        try require(canonicalTools.contains("computer_action"), "aria_bootstrap returned canonical visual tools")
        pass("aria_bootstrap returned Aria control instructions")

        if permissionsResult["screen_recording_trusted"]?.boolValue == true {
            let screenshot = try client.invoke(tool: "computer_snapshot")
            let screenshotResult = try requireRuntimeResult(screenshot, context: "computer_snapshot")
            let width = screenshotResult["width"]?.intValue ?? 0
            let height = screenshotResult["height"]?.intValue ?? 0
            let imageBase64 = screenshotResult["image_base64"]?.stringValue ?? ""
            try require(width > 0 && height > 0 && !imageBase64.isEmpty, "computer_snapshot returned image data")
            pass("computer_snapshot returned \(width)x\(height)")
        } else {
            skip("computer_snapshot skipped because Screen Recording permission is not granted")
        }
    }

    private static func runMCPSmoke(executablePath: String) throws {
        print("Aria MCP smoke test")
        let client = try MCPProcessClient(executableURL: URL(fileURLWithPath: executablePath))
        defer { client.shutdown() }

        let initialize = try client.request(
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-03-26"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("aria-runtime-smoke"),
                    "version": .string("1.0"),
                ]),
            ])
        )
        let initResult = try requireObject(initialize.result, context: "initialize")
        try require(initResult["serverInfo"]?["name"]?.stringValue == "aria-runtime", "initialize returned the aria-runtime server name")
        try require(initResult["instructions"]?.stringValue?.contains("Aria is the control layer for Codex") == true, "initialize returned Aria control instructions")
        pass("MCP initialize succeeded")

        try client.notify(method: "notifications/initialized")

        let toolsResponse = try client.request(method: "tools/list")
        let toolsResult = try requireObject(toolsResponse.result, context: "tools/list")
        let toolNames = Set((toolsResult["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue })
        try require(toolNames.contains("runtime_health"), "MCP tools/list includes runtime_health")
        try require(toolNames.contains("runtime_permissions"), "MCP tools/list includes runtime_permissions")
        try require(toolNames.contains("aria_bootstrap"), "MCP tools/list includes aria_bootstrap")
        try require(toolNames.contains("computer_snapshot"), "MCP tools/list includes computer_snapshot")
        try require(toolNames.contains("computer_action"), "MCP tools/list includes computer_action")
        pass("MCP tools/list returned \(toolNames.count) tools")

        let healthCall = try client.request(
            method: "tools/call",
            params: .object([
                "name": .string("runtime_health"),
                "arguments": .object([:]),
            ])
        )
        let healthStructured = try requireStructuredContent(healthCall, context: "tools/call runtime_health")
        try require(healthStructured["service"]?.stringValue == "aria-runtime", "runtime_health via MCP returned the expected service name")
        pass("MCP runtime_health tool call succeeded")

        let permissionsCall = try client.request(
            method: "tools/call",
            params: .object([
                "name": .string("runtime_permissions"),
                "arguments": .object([:]),
            ])
        )
        let permissionsStructured = try requireStructuredContent(permissionsCall, context: "tools/call runtime_permissions")
        pass("MCP runtime_permissions tool call succeeded")

        let bootstrapCall = try client.request(
            method: "tools/call",
            params: .object([
                "name": .string("aria_bootstrap"),
                "arguments": .object([:]),
            ])
        )
        let bootstrapStructured = try requireStructuredContent(bootstrapCall, context: "tools/call aria_bootstrap")
        try require((bootstrapStructured["canonical_visual_tools"]?.arrayValue ?? []).contains(.string("computer_snapshot")), "aria_bootstrap returned canonical visual tools")
        pass("MCP aria_bootstrap tool call succeeded")

        if permissionsStructured["screen_recording_trusted"]?.boolValue == true {
            let screenshotCall = try client.request(
                method: "tools/call",
                params: .object([
                    "name": .string("computer_snapshot"),
                    "arguments": .object([:]),
                ])
            )
            let screenshotStructured = try requireStructuredContent(screenshotCall, context: "tools/call computer_snapshot")
            let width = screenshotStructured["width"]?.intValue ?? 0
            let height = screenshotStructured["height"]?.intValue ?? 0
            let imageBase64 = screenshotStructured["image_base64"]?.stringValue ?? ""
            try require(width > 0 && height > 0 && !imageBase64.isEmpty, "computer_snapshot via MCP returned image data")
            pass("MCP computer_snapshot returned \(width)x\(height)")
        } else {
            skip("MCP computer_snapshot skipped because Screen Recording permission is not granted")
        }
    }

    private static func runCodexJSONLSmoke(executablePath: String) throws {
        print("Aria Codex JSONL smoke test")
        let client = try JSONLMCPProcessClient(executableURL: URL(fileURLWithPath: executablePath))
        defer { client.shutdown() }

        let initialize = try client.request(
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("aria-runtime-codex-smoke"),
                    "version": .string("1.0"),
                ]),
            ])
        )
        let initResult = try requireObject(initialize.result, context: "jsonl initialize")
        try require(initResult["serverInfo"]?["name"]?.stringValue == "aria-runtime", "JSONL initialize returned the aria-runtime server name")
        pass("JSONL initialize succeeded")

        try client.notify(method: "notifications/initialized")

        let resources = try client.request(method: "resources/list")
        let resourcesResult = try requireObject(resources.result, context: "resources/list")
        let resourceList = resourcesResult["resources"]?.arrayValue ?? []
        try require(resourceList.contains(where: { $0["uri"]?.stringValue == "aria://policy/computer-use" }), "JSONL resources/list includes Aria policy resource")
        pass("JSONL resources/list succeeded")

        let resourceRead = try client.request(
            method: "resources/read",
            params: .object([
                "uri": .string("aria://policy/computer-use"),
            ])
        )
        let resourceReadResult = try requireObject(resourceRead.result, context: "resources/read")
        let contents = resourceReadResult["contents"]?.arrayValue ?? []
        try require(contents.first?["text"]?.stringValue?.contains("Mandatory rules") == true, "JSONL resources/read returned Aria policy text")
        pass("JSONL resources/read succeeded")

        let prompts = try client.request(method: "prompts/list")
        let promptsResult = try requireObject(prompts.result, context: "prompts/list")
        let promptNames = Set((promptsResult["prompts"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue })
        try require(promptNames.contains("aria_computer_use"), "JSONL prompts/list includes aria_computer_use")
        pass("JSONL prompts/list succeeded")

        let promptGet = try client.request(
            method: "prompts/get",
            params: .object([
                "name": .string("aria_computer_use"),
                "arguments": .object([
                    "task": .string("Open Notes and draft a bug triage note"),
                ]),
            ])
        )
        let promptGetResult = try requireObject(promptGet.result, context: "prompts/get")
        let promptMessages = promptGetResult["messages"]?.arrayValue ?? []
        try require(promptMessages.first?["content"]?["text"]?.stringValue?.contains("Call aria_bootstrap first") == true, "JSONL prompts/get returned the Aria control prompt")
        pass("JSONL prompts/get succeeded")

        let tools = try client.request(method: "tools/list", params: .object([
            "_meta": .object([
                "progressToken": .number(0),
            ]),
        ]))
        let toolsResult = try requireObject(tools.result, context: "jsonl tools/list")
        let toolNames = Set((toolsResult["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue })
        try require(toolNames.contains("runtime_health"), "JSONL tools/list includes runtime_health")
        try require(toolNames.contains("computer_snapshot"), "JSONL tools/list includes computer_snapshot")
        pass("JSONL tools/list returned \(toolNames.count) tools")

        let healthCall = try client.request(
            method: "tools/call",
            params: .object([
                "name": .string("runtime_health"),
                "arguments": .object([:]),
            ])
        )
        let structured = try requireStructuredContent(healthCall, context: "jsonl tools/call runtime_health")
        try require(structured["service"]?.stringValue == "aria-runtime", "JSONL runtime_health returned the expected service name")
        pass("JSONL runtime_health tool call succeeded")
    }

    private static func requireRuntimeResult(_ response: RuntimeResponse, context: String) throws -> [String: JSONValue] {
        guard response.ok, let result = response.result?.objectValue else {
            let message = response.error?.message ?? "missing result"
            throw SmokeFailure(description: "\(context) failed: \(message)")
        }
        return result
    }

    private static func requireStructuredContent(_ response: MCPJSONRPCResponse, context: String) throws -> [String: JSONValue] {
        let result = try requireObject(response.result, context: context)
        if result["isError"]?.boolValue == true {
            let payload = result["structuredContent"].map(renderJSON) ?? "{}"
            throw SmokeFailure(description: "\(context) returned an MCP tool error: \(payload)")
        }
        guard let structured = result["structuredContent"]?.objectValue else {
            throw SmokeFailure(description: "\(context) did not return structuredContent")
        }
        return structured
    }

    private static func requireObject(_ value: JSONValue?, context: String) throws -> [String: JSONValue] {
        guard let object = value?.objectValue else {
            throw SmokeFailure(description: "\(context) did not return an object")
        }
        return object
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw SmokeFailure(description: message)
        }
    }

    private static func pass(_ message: String) {
        print("[PASS] \(message)")
    }

    private static func skip(_ message: String) {
        print("[SKIP] \(message)")
    }

    private static func renderJSON(_ value: JSONValue) -> String {
        do {
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return #"{"error":"encoding_failed"}"#
        }
    }
}
