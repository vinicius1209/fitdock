import Foundation
import Network

/// Servidor HTTP mínimo na rede local. Só aceita escrita (o celular envia o snapshot);
/// não há rota que devolva dados de saúde.
final class SnapshotServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fitdock.server")
    private let port: UInt16
    private var token: String
    private var listener: NWListener?
    private let onSnapshot: @Sendable (Snapshot) -> Void
    private let onStatus: @Sendable (String) -> Void

    private static let maxRequestBytes = 2_000_000

    init(port: UInt16, token: String,
         onSnapshot: @escaping @Sendable (Snapshot) -> Void,
         onStatus: @escaping @Sendable (String) -> Void) {
        self.port = port
        self.token = token
        self.onSnapshot = onSnapshot
        self.onStatus = onStatus
    }

    func setToken(_ value: String) {
        queue.async { self.token = value }
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.service = NWListener.Service(name: "FitDock", type: "_fitdock._tcp")
            listener.stateUpdateHandler = { [onStatus, port] state in
                switch state {
                case .ready: onStatus("Recebendo na porta \(port)")
                case .failed(let error): onStatus("Servidor parou: \(error.localizedDescription)")
                case .waiting(let error): onStatus("Aguardando rede: \(error.localizedDescription)")
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            onStatus("Não consegui abrir a porta \(port): \(error.localizedDescription)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > Self.maxRequestBytes {
                self.respond(connection, status: 413, body: ["error": "payload_too_large"])
                return
            }
            if let request = HTTPRequest.parse(buffer) {
                self.route(request, connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func route(_ request: HTTPRequest, _ connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/v1/ping"):
            respond(connection, status: 200, body: ["app": "fitdock", "version": "1"])
        case ("POST", "/v1/snapshot"):
            let expected = "bearer \(token.lowercased())"
            guard request.headers["authorization"]?.lowercased() == expected else {
                respond(connection, status: 401, body: ["error": "invalid_code"])
                return
            }
            do {
                let snapshot = try JSON.decoder.decode(Snapshot.self, from: request.body)
                onSnapshot(snapshot)
                respond(connection, status: 200, body: ["ok": "true"])
            } catch {
                respond(connection, status: 400, body: ["error": "invalid_payload", "detail": "\(error)"])
            }
        default:
            respond(connection, status: 404, body: ["error": "not_found"])
        }
    }

    private func respond(_ connection: NWConnection, status: Int, body: [String: String]) {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 413: "Payload Too Large"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(payload.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    /// Devolve nil enquanto a requisição ainda não chegou inteira.
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headText = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = headText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return nil }
        let body = buffer[bodyStart..<(bodyStart + length)]
        return HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(body))
    }
}

enum LocalNetwork {
    /// Endereços IPv4 do Mac na rede local, para pareamento manual.
    static func ipv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = pointer.pointee
            guard let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }
}
