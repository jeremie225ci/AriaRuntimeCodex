import Foundation

public enum RuntimeMethod: String, Codable, Sendable {
    case health = "runtime.health"
    case permissions = "runtime.permissions"
    case requestPermissions = "runtime.permissions.request"
    case tools = "runtime.tools"
    case invoke = "runtime.invoke"
}

public struct RuntimePaths: Sendable {
    public static let appDirectoryName = "AriaRuntime"

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    public static var logDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    public static var socketURL: URL {
        supportDirectory.appendingPathComponent("runtime.sock", isDirectory: false)
    }
}

public struct RuntimeRequest: Codable, Sendable {
    public let id: String
    public let method: RuntimeMethod
    public let params: JSONValue?

    public init(id: String = UUID().uuidString, method: RuntimeMethod, params: JSONValue? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct RuntimeResponse: Codable, Sendable {
    public let id: String
    public let ok: Bool
    public let result: JSONValue?
    public let error: RuntimeErrorPayload?

    public init(id: String, ok: Bool, result: JSONValue? = nil, error: RuntimeErrorPayload? = nil) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(id: String, result: JSONValue) -> RuntimeResponse {
        RuntimeResponse(id: id, ok: true, result: result)
    }

    public static func failure(id: String, code: String, message: String, details: JSONValue? = nil) -> RuntimeResponse {
        RuntimeResponse(id: id, ok: false, error: RuntimeErrorPayload(code: code, message: message, details: details))
    }
}

public struct RuntimeErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
    public let details: JSONValue?

    public init(code: String, message: String, details: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

public struct RuntimeToolCall: Codable, Sendable {
    public let tool: String
    public let arguments: JSONValue

    public init(tool: String, arguments: JSONValue = .object([:])) {
        self.tool = tool
        self.arguments = arguments
    }
}

public struct ToolDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public enum RuntimeProtocolError: Error, CustomStringConvertible, Sendable {
    case invalidParameters(String)
    case toolNotFound(String)
    case runtimeFailure(String)

    public var description: String {
        switch self {
        case .invalidParameters(let message):
            return message
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .runtimeFailure(let message):
            return message
        }
    }
}

public extension JSONEncoder {
    static func runtimeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return encoder
    }
}
