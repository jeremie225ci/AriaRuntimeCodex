import AppKit
import AriaRuntimeMacOS
import AriaRuntimeShared
import Foundation

@MainActor
final class StatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private let launchAgentManager = LaunchAgentManager()
    private let runtimeService = MacOSRuntimeService()
    private var statusItem: NSStatusItem!
    private var daemonStatusItem: NSMenuItem!
    private var socketStatusItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshMenuState()

        Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(refreshMenuStateTimerFired), userInfo: nil, repeats: true)

        do {
            try ensureDaemonInstalledAndRunning()
            beginPermissionOnboardingIfNeeded()
        } catch {
            showAlert(title: "Aria Runtime", message: "Failed to start daemon automatically:\n\(error)")
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Aria"

        let menu = NSMenu()

        daemonStatusItem = NSMenuItem(title: "Daemon: unknown", action: nil, keyEquivalent: "")
        daemonStatusItem.isEnabled = false
        menu.addItem(daemonStatusItem)

        socketStatusItem = NSMenuItem(title: "Socket: unknown", action: nil, keyEquivalent: "")
        socketStatusItem.isEnabled = false
        menu.addItem(socketStatusItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Start Daemon", action: #selector(startDaemon)))
        menu.addItem(makeItem(title: "Stop Daemon", action: #selector(stopDaemon)))
        menu.addItem(makeItem(title: "Install Launch Agent", action: #selector(installLaunchAgent)))
        menu.addItem(makeItem(title: "Uninstall Launch Agent", action: #selector(uninstallLaunchAgent)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Copy Codex MCP Config", action: #selector(copyCodexMCPConfig)))
        menu.addItem(makeItem(title: "Show Health", action: #selector(showHealth)))
        menu.addItem(makeItem(title: "Show Permissions", action: #selector(showPermissions)))
        menu.addItem(makeItem(title: "Request Permissions", action: #selector(requestPermissions)))
        menu.addItem(makeItem(title: "Open Support Folder", action: #selector(openSupportFolder)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit", action: #selector(quitApp)))

        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func ensureDaemonInstalledAndRunning() throws {
        let executablePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("AriaRuntimeApp", isDirectory: false)
        let daemonURL = launchAgentManager.defaultAgentExecutableURL(relativeTo: executablePath)
        let daemonArguments = launchAgentManager.defaultAgentArguments(relativeTo: executablePath)
        try launchAgentManager.install(agentExecutableURL: daemonURL, arguments: daemonArguments)
        refreshMenuState()
    }

    private func refreshMenuState() {
        let executablePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("AriaRuntimeApp", isDirectory: false)
        let status = launchAgentManager.status(executableURL: executablePath)
        daemonStatusItem.title = "Daemon: " + (status.loaded ? "running" : (status.installed ? "installed, stopped" : "not installed"))
        socketStatusItem.title = "Socket: " + (status.socketExists ? "ready" : "missing")
    }

    private func beginPermissionOnboardingIfNeeded() {
        let current = runtimeService.handle(RuntimeRequest(method: .permissions))
        guard let currentPermissions = current.result?.objectValue else { return }

        let accessibilityTrusted = currentPermissions["accessibility_trusted"]?.boolValue ?? false
        let screenRecordingTrusted = currentPermissions["screen_recording_trusted"]?.boolValue ?? false
        guard !accessibilityTrusted || !screenRecordingTrusted else { return }

        _ = runtimeService.handle(RuntimeRequest(method: .requestPermissions))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.finishPermissionOnboarding()
        }
    }

    private func finishPermissionOnboarding() {
        let current = runtimeService.handle(RuntimeRequest(method: .permissions))
        guard let currentPermissions = current.result?.objectValue else { return }

        let accessibilityTrusted = currentPermissions["accessibility_trusted"]?.boolValue ?? false
        let screenRecordingTrusted = currentPermissions["screen_recording_trusted"]?.boolValue ?? false
        guard !accessibilityTrusted || !screenRecordingTrusted else { return }

        if !accessibilityTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        if !screenRecordingTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        showAlert(
            title: "Aria Runtime Permissions",
            message: """
            Aria Runtime needs macOS permissions before Codex can control the machine.

            Turn on:
            - Accessibility for Aria Runtime
            - Screen Recording for Aria Runtime

            Then relaunch Aria Runtime once.
            """
        )
    }

    @objc private func refreshMenuStateTimerFired() {
        refreshMenuState()
    }

    @objc private func startDaemon() {
        do {
            let executablePath = Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent("AriaRuntimeApp", isDirectory: false)
            let daemonURL = launchAgentManager.defaultAgentExecutableURL(relativeTo: executablePath)
            let daemonArguments = launchAgentManager.defaultAgentArguments(relativeTo: executablePath)
            try launchAgentManager.install(agentExecutableURL: daemonURL, arguments: daemonArguments)
            refreshMenuState()
        } catch {
            showAlert(title: "Start Daemon Failed", message: String(describing: error))
        }
    }

    @objc private func stopDaemon() {
        do {
            try launchAgentManager.bootoutIfNeeded()
            refreshMenuState()
        } catch {
            showAlert(title: "Stop Daemon Failed", message: String(describing: error))
        }
    }

    @objc private func installLaunchAgent() {
        startDaemon()
    }

    @objc private func uninstallLaunchAgent() {
        do {
            try launchAgentManager.uninstall()
            refreshMenuState()
        } catch {
            showAlert(title: "Uninstall Failed", message: String(describing: error))
        }
    }

    @objc private func copyCodexMCPConfig() {
        let commandPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("aria", isDirectory: false)
            .path
        let config = MCPConfiguration.codexConfig(commandPath: commandPath)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
        showAlert(title: "Codex MCP Config", message: "The Aria MCP config has been copied to the clipboard.")
    }

    @objc private func showHealth() {
        do {
            let response = try RuntimeClient().send(method: .health)
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(response)
            showAlert(title: "Aria Health", message: String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            showAlert(title: "Aria Health", message: "Failed to query daemon:\n\(error)")
        }
    }

    @objc private func showPermissions() {
        let response = runtimeService.handle(RuntimeRequest(method: .permissions))
        do {
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(response)
            showAlert(title: "Aria Permissions", message: String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            showAlert(title: "Aria Permissions", message: String(describing: error))
        }
    }

    @objc private func requestPermissions() {
        do {
            let response = try RuntimeClient().send(method: .requestPermissions)
            let data = try JSONEncoder.runtimeEncoder(pretty: true).encode(response)
            showAlert(title: "Aria Permission Request", message: String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            showAlert(title: "Aria Permission Request", message: "Failed to request permissions:\n\(error)")
        }
    }

    @objc private func openSupportFolder() {
        NSWorkspace.shared.open(RuntimePaths.supportDirectory)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

@main
@MainActor
struct AriaRuntimeAppMain {
    static func main() {
        if CommandLine.arguments.contains("--background-agent") {
            runBackgroundAgent()
            return
        }

        let application = NSApplication.shared
        let delegate = StatusBarAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private static func runBackgroundAgent() {
        let service = MacOSRuntimeService()
        let server = UnixSocketServer { request in
            service.handle(request)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try server.run()
            } catch {
                fputs("AriaRuntimeApp --background-agent: \(error)\n", stderr)
                exit(1)
            }
        }

        RunLoop.main.run()
    }
}
