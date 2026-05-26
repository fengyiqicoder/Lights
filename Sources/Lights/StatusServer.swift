import Foundation
import Network

extension Notification.Name {
    static let lightsStateChange = Notification.Name("LightsStateChange")
}

enum LightsState: String {
    case executing
    case permission
    case idle
    case off
}

final class StatusServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private(set) var currentState: LightsState = .idle

    init(port: UInt16 = 9876) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: .ipv4(.loopback),
                port: port
            )
            let listener = try NWListener(using: params)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.start(queue: .global(qos: .utility))
            NSLog("[Lights] StatusServer listening on 127.0.0.1:\(port.rawValue)")
        } catch {
            NSLog("[Lights] StatusServer failed to start: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, _, _ in
            guard let self, let data, let req = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            let path = self.parsePath(req)
            let response = self.route(path: path)
            let body = response.body
            let http = """
            HTTP/1.1 \(response.status)\r
            Content-Type: text/plain; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            conn.send(content: Data(http.utf8), completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    private func parsePath(_ request: String) -> String {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private struct Response {
        let status: String
        let body: String
    }

    private func route(path: String) -> Response {
        let cleaned = path.split(separator: "?").first.map(String.init) ?? path
        switch cleaned {
        case "/executing":
            return setState(.executing)
        case "/permission":
            return setState(.permission)
        case "/idle":
            return setState(.idle)
        case "/off":
            return setState(.off)
        case "/status":
            return Response(status: "200 OK", body: currentState.rawValue)
        case "/", "/health":
            return Response(status: "200 OK", body: "lights ok")
        default:
            return Response(status: "404 Not Found", body: "unknown route")
        }
    }

    private func setState(_ state: LightsState) -> Response {
        currentState = state
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .lightsStateChange,
                object: nil,
                userInfo: ["state": state.rawValue]
            )
        }
        return Response(status: "200 OK", body: state.rawValue)
    }
}
