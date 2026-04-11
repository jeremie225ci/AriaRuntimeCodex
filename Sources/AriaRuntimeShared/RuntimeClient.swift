import Foundation

public struct RuntimeClient: Sendable {
    private let client: UnixSocketClient

    public init(socketPath: String = RuntimePaths.socketURL.path) {
        self.client = UnixSocketClient(path: socketPath)
    }

    public func send(method: RuntimeMethod, params: JSONValue? = nil) throws -> RuntimeResponse {
        try client.send(RuntimeRequest(method: method, params: params))
    }

    public func invoke(tool: String, arguments: JSONValue = .object([:])) throws -> RuntimeResponse {
        try send(
            method: .invoke,
            params: .object([
                "tool": .string(tool),
                "arguments": arguments,
            ])
        )
    }
}
