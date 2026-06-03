import Network
import Foundation
import Combine

@MainActor
class TestServer: ObservableObject {
    @Published var log: [String] = []
    @Published var connected = false

    private var connection: NWConnection?

    func connectToMac() {
        log.append("Connecting to 172.20.10.2:9999...")
        let conn = NWConnection(host: "172.20.10.2", port: 9999, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.connected = true
                    self.log.append("✓ Connected to Mac")
                    self.log.append("Waiting for request...")
                    self.receive(conn)
                case .failed(let e):
                    self.log.append("FAILED: \(e)")
                case .cancelled:
                    self.connected = false
                    self.log.append("Disconnected")
                default: break
                }
            }
        }
        conn.start(queue: .global())
    }

    private func receive(_ conn: NWConnection) {
        // Step 1: read length (e.g. "18\n")
        readLine(conn) { [weak self] lengthStr in
            guard let self, let length = Int(lengthStr), length > 0 else { return }
            // Step 2: read exactly that many bytes = the URL
            conn.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, _ in
                guard let self,
                      let urlString = data.flatMap({ String(data: $0, encoding: .utf8) }),
                      let url = URL(string: urlString) else { return }

                Task { @MainActor [weak self] in
                    self?.log.append("─────────────────────")
                    self?.log.append("Got request from Mac")
                    self?.log.append("Fetching: \(urlString)")
                }

                URLSession.shared.dataTask(with: url) { data, _, error in
                    let body = data ?? Data((error?.localizedDescription ?? "error").utf8)
                    var payload = Data("\(body.count)\n".utf8)
                    payload.append(body)

                    Task { @MainActor [weak self] in
                        self?.log.append("✓ Got result (\(body.count) bytes)")
                        self?.log.append("Sending to Mac...")
                        self?.log.append("Waiting for next request...")
                    }
                    conn.send(content: payload, completion: .contentProcessed { _ in
                        Task { @MainActor [weak self] in self?.receive(conn) }
                    })
                }.resume()
            }
        }
    }

    private nonisolated func readLine(_ conn: NWConnection, buffer: Data = Data(), completion: @escaping (String) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, _, error in
            guard let byte = data?.first, error == nil else { return }
            if byte == UInt8(ascii: "\n") {
                completion(String(data: buffer, encoding: .utf8) ?? "")
            } else {
                var buf = buffer
                buf.append(byte)
                self?.readLine(conn, buffer: buf, completion: completion)
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }
}
