import Foundation
import AriaRuntimeMacOS
import AriaRuntimeShared

enum AriaRuntimeCLI {
    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "help" || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        switch args[0] {
        case "setup":
            try SetupCommand.run(args: Array(args.dropFirst()), executablePath: CommandLine.arguments[0])
        case "daemon":
            try runDaemon(args: Array(args.dropFirst()))
        case "mcp":
            try runMCP(args: Array(args.dropFirst()))
        case "codex":
            try CodexIntegration.run(args: Array(args.dropFirst()), executablePath: CommandLine.arguments[0])
        case "status":
            try printStatus()
        case "health":
            try printResponse(RuntimeClient().send(method: .health))
        case "permissions":
            try runPermissions(args: Array(args.dropFirst()))
        case "tools":
            try printResponse(RuntimeClient().send(method: .tools))
        case "doctor":
            try doctor()
        case "smoke":
            try SmokeRunner.run(args: Array(args.dropFirst()), executablePath: CommandLine.arguments[0])
        case "call":
            try callTool(args: Array(args.dropFirst()))
        default:
            throw RuntimeProtocolError.invalidParameters("Unknown aria command: \(args[0])")
        }
    }

    private static func printUsage() {
        print(
            """
            Aria Runtime CLI

            Usage:
              aria daemon --foreground
              aria daemon install-agent
              aria daemon uninstall-agent
              aria daemon status
              aria setup
              aria setup status
              aria setup test-prompt
              aria mcp serve
              aria mcp print-config
              aria codex install
              aria codex status
              aria codex uninstall
              aria codex print-config
              aria status
              aria health
              aria permissions
              aria permissions request
              aria tools
              aria doctor
              aria smoke runtime
              aria smoke mcp
              aria smoke all
              aria call <tool_name> [--json '{"key":"value"}']
            """
        )
    }

    private static func runDaemon(args: [String]) throws {
        let manager = LaunchAgentManager()
        switch args {
        case ["--foreground"]:
            let service = MacOSRuntimeService()
            let server = UnixSocketServer { request in
                service.handle(request)
            }
            runServerWithMainRunLoop(server)
        case ["install-agent"]:
            let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            let agentURL = manager.defaultAgentExecutableURL(relativeTo: executableURL)
            let agentArguments = manager.defaultAgentArguments(relativeTo: executableURL)
            try manager.install(agentExecutableURL: agentURL, arguments: agentArguments)
            print("Installed LaunchAgent: \(manager.plistURL.path)")
        case ["uninstall-agent"]:
            try manager.uninstall()
            print("Uninstalled LaunchAgent: \(manager.plistURL.path)")
        case ["status"]:
            let status = manager.status(executableURL: URL(fileURLWithPath: CommandLine.arguments[0]))
            let payload: JSONValue = .object([
                "installed": .bool(status.installed),
                "loaded": .bool(status.loaded),
                "socket_exists": .bool(status.socketExists),
                "plist_path": .string(status.plistPath),
                "daemon_path": .string(status.daemonPath),
                "arguments": .array(status.arguments.map(JSONValue.string)),
            ])
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(payload)
            print(String(data: data, encoding: .utf8) ?? "{}")
        default:
            throw RuntimeProtocolError.invalidParameters(
                "Supported daemon commands: --foreground, install-agent, uninstall-agent, status"
            )
        }
    }

    private static func runMCP(args: [String]) throws {
        switch args {
        case ["serve"]:
            try MCPServer().run()
        case ["print-config"]:
            let commandPath = URL(fileURLWithPath: CommandLine.arguments[0]).path
            print(MCPConfiguration.codexConfig(commandPath: commandPath))
        default:
            throw RuntimeProtocolError.invalidParameters("Supported MCP commands: serve, print-config")
        }
    }

    private static func runServerWithMainRunLoop(_ server: UnixSocketServer) -> Never {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try server.run()
            } catch {
                fputs("aria daemon: \(error)\n", stderr)
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }

    private static func printStatus() throws {
        let manager = LaunchAgentManager()
        let status = manager.status(executableURL: URL(fileURLWithPath: CommandLine.arguments[0]))
        let payload: JSONValue = .object([
            "launch_agent": .object([
                "installed": .bool(status.installed),
                "loaded": .bool(status.loaded),
                "plist_path": .string(status.plistPath),
                "daemon_path": .string(status.daemonPath),
                "arguments": .array(status.arguments.map(JSONValue.string)),
            ]),
            "socket_exists": .bool(status.socketExists),
        ])
        let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(payload)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func runPermissions(args: [String]) throws {
        switch args {
        case []:
            try printResponse(sendRuntimeOrLocal(method: .permissions))
        case ["request"]:
            try printResponse(sendRuntimeOrLocal(method: .requestPermissions))
        default:
            throw RuntimeProtocolError.invalidParameters("Supported permissions commands: permissions, permissions request")
        }
    }

    private static func sendRuntimeOrLocal(method: RuntimeMethod) throws -> RuntimeResponse {
        do {
            return try RuntimeClient().send(method: method)
        } catch {
            // Permission onboarding must still work before the daemon socket is
            // reachable or when macOS temporarily blocks the installed helper.
            // Falling back to a local service lets `aria permissions request`
            // trigger the native macOS prompts directly from the CLI.
            return MacOSRuntimeService().handle(RuntimeRequest(method: method))
        }
    }

    private static func doctor() throws {
        let client = RuntimeClient()
        let health = try client.send(method: RuntimeMethod.health)
        let permissions = try client.send(method: RuntimeMethod.permissions)
        let tools = try client.send(method: RuntimeMethod.tools)

        print("== Health ==")
        try printResponse(health)
        print("\n== Permissions ==")
        try printResponse(permissions)
        print("\n== Tools ==")
        try printResponse(tools)
    }

    private static func callTool(args: [String]) throws {
        guard let tool = args.first else {
            throw RuntimeProtocolError.invalidParameters("Missing tool name for `aria call`.")
        }

        var jsonArguments = JSONValue.object([:])
        var remaining = Array(args.dropFirst())
        while !remaining.isEmpty {
            let flag = remaining.removeFirst()
            if flag == "--json" {
                guard let rawJSON = remaining.first else {
                    throw RuntimeProtocolError.invalidParameters("Expected JSON after --json")
                }
                remaining.removeFirst()
                let data = Data(rawJSON.utf8)
                jsonArguments = try JSONDecoder().decode(JSONValue.self, from: data)
            } else {
                throw RuntimeProtocolError.invalidParameters("Unknown flag for `aria call`: \(flag)")
            }
        }

        let response = try RuntimeClient().invoke(tool: tool, arguments: jsonArguments)
        try printResponse(response)
    }

    private static func printResponse(_ response: RuntimeResponse) throws {
        let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(response)
        guard let output = String(data: data, encoding: .utf8) else {
            throw RuntimeProtocolError.runtimeFailure("Unable to render JSON response")
        }
        print(output)
    }
}

do {
    try AriaRuntimeCLI.run()
} catch {
    fputs("aria: \(error)\n", stderr)
    exit(1)
}
