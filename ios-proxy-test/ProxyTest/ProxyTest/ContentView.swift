import SwiftUI

struct ContentView: View {
    @StateObject private var server = TestServer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: server.connected ? "link.circle.fill" : "link.circle")
                    .font(.system(size: 64))
                    .foregroundColor(server.connected ? .green : Color(white: 0.3))

                Text(server.connected ? "Connected to Mac" : "Not Connected")
                    .foregroundColor(.white)
                    .font(.title3)

                Button {
                    server.connected ? server.disconnect() : server.connectToMac()
                } label: {
                    Text(server.connected ? "Disconnect" : "Connect to Mac")
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(server.connected ? Color.red : Color.white)
                        .cornerRadius(24)
                }

                if !server.log.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(server.log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(
                                        line.contains("✓") ? .green :
                                        line.contains("FAILED") ? .red :
                                        Color(white: 0.5)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxHeight: 300)
                    .background(Color(white: 0.06))
                    .cornerRadius(8)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }
}
