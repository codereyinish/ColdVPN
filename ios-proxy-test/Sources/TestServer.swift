import Network
import Foundation

class TestServer: ObservableObject {

    @Published var listenerLog: [String] = []
    @Published var urlSessionLog: [String] = []
    @Published var connectionCount = 0

    private var listener: NWListener?

    // ─────────────────────────────────────────────
    // TEST 1 — NWListener: can hotspot clients connect?
    // ─────────────────────────────────────────────
    func startListener() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: 8080)
        } catch {
            log(&listenerLog, "ERROR: Could not create listener — \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.log(&self!.listenerLog, "Listener READY on port 8080")
                self?.log(&self!.listenerLog, "On Mac run: curl http://172.20.10.1:8080")
            case .failed(let err):
                self?.log(&self!.listenerLog, "Listener FAILED: \(err)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connectionCount += 1
            self.log(&self.listenerLog, "✓ Connection #\(self.connectionCount) received!")
            self.log(&self.listenerLog, "  from: \(connection.endpoint)")

            connection.start(queue: .global())

            // Send simple HTTP response back to Mac
            let body = "TEST 1 PASSED — NWListener accepted hotspot connection"
            let response = """
            HTTP/1.1 200 OK\r
            Content-Length: \(body.utf8.count)\r
            \r
            \(body)
            """
            connection.send(
                content: response.data(using: .utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }

        listener?.start(queue: .main)
    }

    func stopListener() {
        listener?.cancel()
        listener = nil
        log(&listenerLog, "Listener stopped")
    }

    // ─────────────────────────────────────────────
    // TEST 2 — URLSession: does it use phone APN?
    // ─────────────────────────────────────────────
    // After running this, check AT&T counter (text myatt to 3282)
    // If AT&T hotspot counter did NOT increase → phone APN ✓
    // If AT&T hotspot counter DID increase     → tethering APN ✗
    func testURLSession() {
        log(&urlSessionLog, "Starting URLSession request...")
        log(&urlSessionLog, "Note AT&T hotspot counter BEFORE this test")
        log(&urlSessionLog, "─────────────────────────────────────")

        // Test 1: check public IP (should be iPhone's IP, not Oracle)
        let ipURL = URL(string: "https://checkip.amazonaws.com")!
        URLSession.shared.dataTask(with: ipURL) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.log(&self.urlSessionLog, "ERROR: \(error.localizedDescription)")
                return
            }
            let ip = data.flatMap { String(data: $0, encoding: .utf8) }?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            self.log(&self.urlSessionLog, "Public IP seen by internet: \(ip)")
            self.log(&self.urlSessionLog, "(should be iPhone's IP, not Oracle VPS)")
        }.resume()

        // Test 2: download 5MB — enough to show on AT&T counter
        let downloadURL = URL(string: "https://proof.ovh.net/files/5Mb.dat")!
        log(&urlSessionLog, "Downloading 5MB via URLSession...")
        let start = Date()

        URLSession.shared.dataTask(with: downloadURL) { [weak self] data, _, error in
            guard let self else { return }
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
            if let error {
                self.log(&self.urlSessionLog, "Download ERROR: \(error.localizedDescription)")
            } else {
                let mb = String(format: "%.2f", Double(data?.count ?? 0) / 1_048_576)
                self.log(&self.urlSessionLog, "Downloaded \(mb) MB in \(elapsed)s")
                self.log(&self.urlSessionLog, "─────────────────────────────────────")
                self.log(&self.urlSessionLog, "Now check AT&T counter (myatt to 3282)")
                self.log(&self.urlSessionLog, "If hotspot counter unchanged → phone APN ✓")
                self.log(&self.urlSessionLog, "If hotspot counter +5MB     → tethering APN ✗")
            }
        }.resume()
    }

    // ─────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────
    private func log(_ target: inout [String], _ message: String) {
        DispatchQueue.main.async {
            target.append(message)
            print(message)
        }
    }
}
