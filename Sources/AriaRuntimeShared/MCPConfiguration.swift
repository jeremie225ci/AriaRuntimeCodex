import Foundation

public enum MCPConfiguration {
    public static func codexConfig(commandPath: String) -> String {
        let payload: [String: Any] = [
            "mcpServers": [
                "aria-runtime": [
                    "command": commandPath,
                    "args": ["mcp", "serve"],
                ],
            ],
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
