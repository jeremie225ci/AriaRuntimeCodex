import Foundation
import AriaRuntimeShared

enum CodexIntegration {
    private static let serverName = "aria-runtime"

    static func run(args: [String], executablePath: String) throws {
        switch args {
        case ["install"]:
            try install(executablePath: executablePath)
        case ["status"], []:
            try status(executablePath: executablePath)
        case ["uninstall"]:
            try uninstall()
        case ["print-config"]:
            let commandPath = ariaCommandPath(from: executablePath)
            print(MCPConfiguration.codexConfig(commandPath: commandPath))
        default:
            throw RuntimeProtocolError.invalidParameters(
                "Supported codex commands: install, status, uninstall, print-config"
            )
        }
    }

    private static func install(executablePath: String) throws {
        let commandPath = ariaCommandPath(from: executablePath)
        let existing = try fetchConfiguration()
        let currentCommand = configuredCommand(from: existing)
        let currentArgs = configuredArgs(from: existing)

        if currentCommand == commandPath, currentArgs == ["mcp", "serve"] {
            print("Codex MCP server `\(serverName)` is already installed.")
            return
        }

        _ = try? runCodex(arguments: ["mcp", "remove", serverName], allowFailure: true)
        _ = try runCodex(arguments: ["mcp", "add", serverName, "--", commandPath, "mcp", "serve"])
        print("Installed Codex MCP server `\(serverName)` with command: \(commandPath) mcp serve")
    }

    private static func status(executablePath: String) throws {
        let expectedCommand = ariaCommandPath(from: executablePath)
        let expectedArgs = ["mcp", "serve"]
        let payload: JSONValue

        if let configuration = try fetchConfiguration() {
            let actualCommand = configuredCommand(from: configuration) ?? ""
            let actualArgs = configuredArgs(from: configuration)
            payload = .object([
                "installed": .bool(true),
                "name": .string(serverName),
                "expected_command": .string(expectedCommand),
                "expected_args": .array(expectedArgs.map(JSONValue.string)),
                "matches_expected_command": .bool(actualCommand == expectedCommand),
                "matches_expected_args": .bool(actualArgs == expectedArgs),
                "matches_expected_configuration": .bool(actualCommand == expectedCommand && actualArgs == expectedArgs),
                "configuration": .object(configuration),
                "command": .string(actualCommand),
                "args": .array(actualArgs.map(JSONValue.string)),
            ])
        } else {
            payload = .object([
                "installed": .bool(false),
                "name": .string(serverName),
                "expected_command": .string(expectedCommand),
                "expected_args": .array(expectedArgs.map(JSONValue.string)),
            ])
        }

        let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(payload)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func uninstall() throws {
        _ = try runCodex(arguments: ["mcp", "remove", serverName], allowFailure: false)
        print("Removed Codex MCP server `\(serverName)`.")
    }

    private static func fetchConfiguration() throws -> [String: JSONValue]? {
        do {
            let output = try runCodex(arguments: ["mcp", "get", serverName, "--json"])
            guard let data = output.data(using: .utf8) else {
                return nil
            }
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            return value.objectValue
        } catch {
            return nil
        }
    }

    private static func configuredCommand(from configuration: [String: JSONValue]?) -> String? {
        guard let configuration else { return nil }
        if let command = configuration["command"]?.stringValue {
            return command
        }
        return configuration["transport"]?["command"]?.stringValue
    }

    private static func configuredArgs(from configuration: [String: JSONValue]?) -> [String] {
        guard let configuration else { return [] }
        if let args = configuration["args"]?.arrayValue?.compactMap(\.stringValue), !args.isEmpty {
            return args
        }
        return configuration["transport"]?["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private static func ariaCommandPath(from executablePath: String) -> String {
        let executableURL = URL(fileURLWithPath: executablePath)
        if executableURL.lastPathComponent == "aria" {
            return executableURL.path
        }

        let sibling = executableURL.deletingLastPathComponent().appendingPathComponent("aria", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling.path
        }

        return executableURL.path
    }

    @discardableResult
    private static func runCodex(arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex"] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutString = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrString = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let filteredStderr = stderrString
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("WARNING: proceeding, even though we could not update PATH:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [stdoutString, filteredStderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: filteredStderr.isEmpty ? "" : "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 && !allowFailure {
            throw RuntimeProtocolError.runtimeFailure(
                combined.isEmpty
                    ? "codex \(arguments.joined(separator: " ")) failed"
                    : "codex \(arguments.joined(separator: " ")) failed: \(combined)"
            )
        }

        return combined
    }
}
