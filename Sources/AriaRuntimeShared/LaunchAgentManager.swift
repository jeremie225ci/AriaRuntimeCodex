import Foundation

public struct LaunchAgentStatus: Sendable {
    public let installed: Bool
    public let loaded: Bool
    public let socketExists: Bool
    public let plistPath: String
    public let daemonPath: String
    public let arguments: [String]
}

public final class LaunchAgentManager: @unchecked Sendable {
    public static let label = "com.getariaos.runtime.daemon"

    public init() {}

    public var plistURL: URL {
        let libraryRoot = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return libraryRoot
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist", isDirectory: false)
    }

    public func defaultAgentExecutableURL(relativeTo executableURL: URL) -> URL {
        let resolvedExecutableURL = executableURL.resolvingSymlinksInPath()
        let baseDirectory = resolvedExecutableURL.deletingLastPathComponent()
        let appExecutable = baseDirectory.appendingPathComponent("AriaRuntimeApp", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: appExecutable.path) {
            return appExecutable
        }

        let daemonExecutable = baseDirectory.appendingPathComponent("aria-runtime-daemon", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: daemonExecutable.path) {
            return daemonExecutable
        }

        if resolvedExecutableURL.lastPathComponent == "AriaRuntimeApp" || resolvedExecutableURL.lastPathComponent == "aria-runtime-daemon" {
            return resolvedExecutableURL
        }

        return appExecutable
    }

    public func defaultAgentArguments(relativeTo executableURL: URL) -> [String] {
        let executable = defaultAgentExecutableURL(relativeTo: executableURL)
        return executable.lastPathComponent == "AriaRuntimeApp" ? ["--background-agent"] : []
    }

    public func install(agentExecutableURL: URL, arguments: [String] = []) throws {
        let executablePath = agentExecutableURL.path
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw RuntimeProtocolError.runtimeFailure("Agent executable not found or not executable at \(executablePath)")
        }

        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: RuntimePaths.logDirectory, withIntermediateDirectories: true)

        let payload = launchAgentPayload(executablePath: executablePath, arguments: arguments)
        let plistData = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try plistData.write(to: plistURL, options: .atomic)

        try bootoutIfNeeded()
        try runLaunchctl(["bootstrap", guiDomain, plistURL.path], allowFailure: false)
        try runLaunchctl(["kickstart", "-k", "\(guiDomain)/\(Self.label)"], allowFailure: false)
    }

    public func uninstall() throws {
        try bootoutIfNeeded()
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    public func bootstrap() throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw RuntimeProtocolError.runtimeFailure("LaunchAgent plist does not exist at \(plistURL.path)")
        }
        try runLaunchctl(["bootstrap", guiDomain, plistURL.path], allowFailure: false)
        try runLaunchctl(["kickstart", "-k", "\(guiDomain)/\(Self.label)"], allowFailure: false)
    }

    public func bootoutIfNeeded() throws {
        _ = try? runLaunchctl(["bootout", "\(guiDomain)/\(Self.label)"], allowFailure: true)
    }

    public func status(executableURL: URL) -> LaunchAgentStatus {
        let agentURL = defaultAgentExecutableURL(relativeTo: executableURL)
        let arguments = defaultAgentArguments(relativeTo: executableURL)
        let installed = FileManager.default.fileExists(atPath: plistURL.path)
        let socketExists = FileManager.default.fileExists(atPath: RuntimePaths.socketURL.path)
        let loaded = (try? runLaunchctl(["print", "\(guiDomain)/\(Self.label)"], allowFailure: false)) != nil
        return LaunchAgentStatus(
            installed: installed,
            loaded: loaded,
            socketExists: socketExists,
            plistPath: plistURL.path,
            daemonPath: agentURL.path,
            arguments: arguments
        )
    }

    private var guiDomain: String {
        "gui/\(getuid())"
    }

    private func launchAgentPayload(executablePath: String, arguments: [String]) -> [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": [executablePath] + arguments,
            "RunAtLoad": true,
            "KeepAlive": true,
            "WorkingDirectory": RuntimePaths.supportDirectory.path,
            "StandardOutPath": RuntimePaths.logDirectory.appendingPathComponent("daemon.stdout.log").path,
            "StandardErrorPath": RuntimePaths.logDirectory.appendingPathComponent("daemon.stderr.log").path,
            "ProcessType": "Interactive",
        ]
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String], allowFailure: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !allowFailure {
            let detail = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeProtocolError.runtimeFailure("launchctl \(arguments.joined(separator: " ")) failed: \(detail)")
        }

        return output.isEmpty ? errorOutput : output
    }
}
