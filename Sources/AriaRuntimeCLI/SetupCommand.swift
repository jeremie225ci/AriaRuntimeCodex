import Foundation
import AriaRuntimeMacOS
import AriaRuntimeShared

enum SetupCommand {
    static func run(args: [String], executablePath: String) throws {
        switch args {
        case []:
            try setup(executablePath: executablePath)
        case ["status"]:
            try printStatus(executablePath: executablePath)
        case ["test-prompt"]:
            print(AriaControlPlane.setupTestPrompt())
        default:
            throw RuntimeProtocolError.invalidParameters("Supported setup commands: setup, setup status, setup test-prompt")
        }
    }

    private static func setup(executablePath: String) throws {
        let executableURL = URL(fileURLWithPath: executablePath)
        let launchAgentManager = LaunchAgentManager()
        let agentURL = launchAgentManager.defaultAgentExecutableURL(relativeTo: executableURL)
        let agentArguments = launchAgentManager.defaultAgentArguments(relativeTo: executableURL)

        try launchAgentManager.install(agentExecutableURL: agentURL, arguments: agentArguments)

        if commandExists("codex") {
            try CodexIntegration.run(args: ["install"], executablePath: executablePath)
        }

        var permissionRequest: RuntimeResponse?
        var permissions: [String: JSONValue]?
        if (try? waitForRuntimeReady(timeoutSeconds: 20)) != nil {
            let client = RuntimeClient()
            permissionRequest = try? client.send(method: .requestPermissions)
            permissions = try? currentPermissions(client: client)
        }

        let status = try statusPayload(executablePath: executablePath, permissionRequest: permissionRequest)
        let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(status)
        if let output = String(data: data, encoding: .utf8) {
            print(output)
        }

        let accessibilityTrusted = permissions?["accessibility_trusted"]?.boolValue ?? false
        let screenRecordingTrusted = permissions?["screen_recording_trusted"]?.boolValue ?? false
        print("")
        print("Next:")
        if accessibilityTrusted && screenRecordingTrusted {
            print("  codex")
            print("  \(AriaControlPlane.setupTestPrompt())")
            print("  Aria has set Codex's default profile to `aria` for visual tasks.")
        } else {
            print("  Finish the macOS permission prompts for Aria Runtime.")
            print("  Then relaunch or rerun: aria setup")
        }
    }

    private static func printStatus(executablePath: String) throws {
        let payload = try statusPayload(executablePath: executablePath, permissionRequest: nil)
        let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(payload)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func statusPayload(executablePath: String, permissionRequest: RuntimeResponse?) throws -> JSONValue {
        let executableURL = URL(fileURLWithPath: executablePath)
        let launchAgentManager = LaunchAgentManager()
        let launchAgentStatus = launchAgentManager.status(executableURL: executableURL)
        let launchAgentPayload: JSONValue = .object([
            "installed": .bool(launchAgentStatus.installed),
            "loaded": .bool(launchAgentStatus.loaded),
            "socket_exists": .bool(launchAgentStatus.socketExists),
            "plist_path": .string(launchAgentStatus.plistPath),
            "daemon_path": .string(launchAgentStatus.daemonPath),
            "arguments": .array(launchAgentStatus.arguments.map(JSONValue.string)),
        ])

        let runtimeStatus: JSONValue
        let permissionsStatus: JSONValue
        do {
            let client = RuntimeClient()
            let health = try requireResultObject(client.send(method: .health))
            let permissions = try currentPermissions(client: client)
            runtimeStatus = .object(health)
            permissionsStatus = .object(permissions)
        } catch {
            runtimeStatus = .object([
                "ok": .bool(false),
                "error": .string(String(describing: error)),
            ])
            let localPermissions = MacOSRuntimeService().handle(RuntimeRequest(method: .permissions))
            if localPermissions.ok, let result = localPermissions.result {
                permissionsStatus = result
            } else {
                permissionsStatus = .object([
                    "ok": .bool(false),
                    "error": .string(String(describing: error)),
                ])
            }
        }

        var payload: [String: JSONValue] = [
            "launch_agent": launchAgentPayload,
            "runtime": runtimeStatus,
            "permissions": permissionsStatus,
            "codex": CodexIntegration.statusPayload(executablePath: executablePath),
            "recommended_test_prompt": .string(AriaControlPlane.setupTestPrompt()),
        ]
        if let permissionRequest {
            payload["permission_request"] = runtimeResponsePayload(permissionRequest)
        }
        return .object(payload)
    }

    private static func waitForRuntimeReady(timeoutSeconds: Int) throws -> [String: JSONValue] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        let client = RuntimeClient()
        while Date() < deadline {
            if let response = try? client.send(method: .health),
               response.ok,
               let result = response.result?.objectValue {
                return result
            }
            usleep(500_000)
        }
        throw RuntimeProtocolError.runtimeFailure("Timed out waiting for the local Aria runtime daemon to become ready.")
    }

    private static func currentPermissions(client: RuntimeClient) throws -> [String: JSONValue] {
        try requireResultObject(client.send(method: .permissions))
    }

    private static func requireResultObject(_ response: RuntimeResponse) throws -> [String: JSONValue] {
        guard response.ok, let result = response.result?.objectValue else {
            throw RuntimeProtocolError.runtimeFailure(response.error?.message ?? "missing runtime result")
        }
        return result
    }

    private static func runtimeResponsePayload(_ response: RuntimeResponse) -> JSONValue {
        var payload: [String: JSONValue] = [
            "id": .string(response.id),
            "ok": .bool(response.ok),
        ]
        if let result = response.result {
            payload["result"] = result
        }
        if let error = response.error {
            payload["error"] = .object([
                "code": .string(error.code),
                "message": .string(error.message),
                "details": error.details ?? .null,
            ])
        }
        return .object(payload)
    }

    private static func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-lc", "command -v \(name) >/dev/null 2>&1"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
