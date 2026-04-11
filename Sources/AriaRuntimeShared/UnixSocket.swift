import Dispatch
import Foundation
import Darwin

public enum UnixSocketError: Error, CustomStringConvertible, Sendable {
    case createFailed(String)
    case bindFailed(String)
    case listenFailed(String)
    case connectFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case decodeFailed(String)
    case pathTooLong(String)

    public var description: String {
        switch self {
        case .createFailed(let message),
             .bindFailed(let message),
             .listenFailed(let message),
             .connectFailed(let message),
             .writeFailed(let message),
             .readFailed(let message),
             .decodeFailed(let message),
             .pathTooLong(let message):
            return message
        }
    }
}

public final class UnixSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (RuntimeRequest) -> RuntimeResponse

    private let path: String
    private let handler: Handler
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder.runtimeEncoder()

    public init(path: String = RuntimePaths.socketURL.path, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func run() throws {
        try FileManager.default.createDirectory(
            at: RuntimePaths.supportDirectory,
            withIntermediateDirectories: true
        )
        _ = unlink(path)

        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw UnixSocketError.createFailed(String(cString: strerror(errno)))
        }

        var address = try Self.makeAddress(path: path)
        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rawPointer in
                Darwin.bind(serverFD, rawPointer, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }

        guard bindResult == 0 else {
            close(serverFD)
            throw UnixSocketError.bindFailed(String(cString: strerror(errno)))
        }

        guard listen(serverFD, SOMAXCONN) == 0 else {
            close(serverFD)
            throw UnixSocketError.listenFailed(String(cString: strerror(errno)))
        }

        chmod(path, mode_t(0o600))

        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                throw UnixSocketError.readFailed(String(cString: strerror(errno)))
            }

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                self.handleConnection(clientFD)
            }
        }
    }

    private func handleConnection(_ fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(fd, &chunk, chunk.count)
            if bytesRead == 0 {
                return
            }
            if bytesRead < 0 {
                return
            }

            buffer.append(chunk, count: bytesRead)

            while let newlineRange = buffer.firstRange(of: Data([0x0a])) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                if line.isEmpty {
                    continue
                }

                let response: RuntimeResponse
                do {
                    let request = try decoder.decode(RuntimeRequest.self, from: line)
                    response = handler(request)
                } catch {
                    response = .failure(
                        id: "decode-error",
                        code: "invalid_request",
                        message: "Failed to decode request: \(error)"
                    )
                }

                do {
                    try Self.write(response, to: fd, encoder: encoder)
                } catch {
                    return
                }
            }
        }
    }

    private static func write(_ response: RuntimeResponse, to fd: Int32, encoder: JSONEncoder) throws {
        var data = try encoder.encode(response)
        data.append(0x0a)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw UnixSocketError.writeFailed("Missing response bytes")
            }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), remaining)
                if written < 0 {
                    throw UnixSocketError.writeFailed(String(cString: strerror(errno)))
                }
                remaining -= written
                offset += written
            }
        }
    }

    static func makeAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        #if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
        #endif
        address.sun_family = sa_family_t(AF_UNIX)

        let bytes = path.utf8CString
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= maxPathLength else {
            throw UnixSocketError.pathTooLong(path)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            let charBuffer = rawBuffer.bindMemory(to: CChar.self)
            charBuffer.initialize(repeating: 0)
            for (index, byte) in bytes.enumerated() {
                charBuffer[index] = byte
            }
        }

        return address
    }
}

public struct UnixSocketClient: Sendable {
    public let path: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder.runtimeEncoder()

    public init(path: String = RuntimePaths.socketURL.path) {
        self.path = path
    }

    public func send(_ request: RuntimeRequest) throws -> RuntimeResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixSocketError.createFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        var address = try UnixSocketServer.makeAddress(path: path)
        let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rawPointer in
                Darwin.connect(fd, rawPointer, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }

        guard connectResult == 0 else {
            throw UnixSocketError.connectFailed(String(cString: strerror(errno)))
        }

        var payload = try encoder.encode(request)
        payload.append(0x0a)

        try payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw UnixSocketError.writeFailed("Missing request bytes")
            }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), remaining)
                if written < 0 {
                    throw UnixSocketError.writeFailed(String(cString: strerror(errno)))
                }
                remaining -= written
                offset += written
            }
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = Darwin.read(fd, &chunk, chunk.count)
            if bytesRead == 0 {
                break
            }
            if bytesRead < 0 {
                throw UnixSocketError.readFailed(String(cString: strerror(errno)))
            }
            buffer.append(chunk, count: bytesRead)
            if let newlineRange = buffer.firstRange(of: Data([0x0a])) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                return try decoder.decode(RuntimeResponse.self, from: line)
            }
        }

        throw UnixSocketError.readFailed("Socket closed before response")
    }
}
