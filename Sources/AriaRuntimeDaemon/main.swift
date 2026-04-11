import Foundation
import AriaRuntimeShared
import AriaRuntimeMacOS

let service = MacOSRuntimeService()
let server = UnixSocketServer { request in
    service.handle(request)
}

DispatchQueue.global(qos: .userInitiated).async {
    do {
        try server.run()
    } catch {
        fputs("aria-runtime-daemon: \(error)\n", stderr)
        exit(1)
    }
}

RunLoop.main.run()
