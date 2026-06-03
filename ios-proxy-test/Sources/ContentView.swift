import SwiftUI

struct ContentView: View {
    @StateObject private var server = TestServer()

    var body: some View {
        NavigationView {
            List {
                // ── TEST 1 ──
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Can Mac connect to iPhone proxy over hotspot?")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Start Listener") {
                                server.startListener()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Stop") {
                                server.stopListener()
                            }
                            .buttonStyle(.bordered)
                        }

                        if !server.listenerLog.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(server.listenerLog, id: \.self) { line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(line.contains("✓") ? .green :
                                                         line.contains("ERROR") ? .red : .primary)
                                }
                            }
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                } header: {
                    Label("Test 1 — NWListener", systemImage: "network")
                }

                // ── TEST 2 ──
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Does URLSession use phone APN or tethering APN?")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Run URLSession Test") {
                            server.testURLSession()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        if !server.urlSessionLog.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(server.urlSessionLog, id: \.self) { line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(line.contains("✓") ? .green :
                                                         line.contains("✗") ? .red :
                                                         line.contains("─") ? .secondary : .primary)
                                }
                            }
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                } header: {
                    Label("Test 2 — URLSession APN", systemImage: "antenna.radiowaves.left.and.right")
                }

                // ── Instructions ──
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Test 1 steps:")
                            .font(.caption).bold()
                        Text("1. Tap Start Listener\n2. Connect Mac to iPhone hotspot\n3. On Mac run:\n   curl http://172.20.10.1:8080\n4. Watch for connection here")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Divider()

                        Text("Test 2 steps:")
                            .font(.caption).bold()
                        Text("1. Connect Mac to iPhone hotspot\n2. Text 'myatt' to 3282 — note hotspot GB\n3. Tap Run URLSession Test\n4. Wait for download to finish\n5. Text 'myatt' again\n6. Check if hotspot GB changed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Instructions", systemImage: "list.number")
                }
            }
            .navigationTitle("Proxy Tests")
        }
    }
}
