import Cocoa

// wg-monitor.swift — a tiny menu-bar widget for the VPN.
// Shows VPN status + client transfer + VPS load/conns/latency (via the `wg-monitor`
// CLI in this folder), and toggles the tunnel. Lives only in the menu bar.
//
// Build:  swiftc wg-monitor.swift -o WGMonitor
// Run:    ./WGMonitor        (needs `wg-monitor` on PATH, e.g. /usr/local/bin)

let MONITOR  = "wg-monitor"   // the CLI; install to /usr/local/bin or adjust PATH
let WG_IFACE = "wg0"

func sh(_ command: String) -> String {
    let p = Process()
    p.launchPath = "/bin/bash"
    p.arguments = ["-lc", command]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

func human(_ bytes: Double) -> String {
    let u = ["B", "KB", "MB", "GB", "TB"]; var b = bytes; var i = 0
    while b >= 1024 && i < 4 { b /= 1024; i += 1 }
    return String(format: "%.1f %@", b, u[i])
}

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "WG …"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in self.refresh() }
    }

    func mi(_ title: String, _ sel: Selector? = nil, _ key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        if sel != nil { m.target = self }
        return m
    }

    @objc func refresh() {
        let out = sh("\(MONITOR) --json")
        var up = false, rx = 0.0, tx = 0.0
        var load = "-", conns = "-", lat = "-"
        if let d = out.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            up = num(o["up"]) == 1
            rx = num(o["rx"]); tx = num(o["tx"])
            load = o["load"] as? String ?? "-"
            conns = o["conns"] as? String ?? "-"
            lat = o["latency"] as? String ?? "-"
        }
        item.button?.title = up ? "WG ●" : "WG ○"

        let menu = NSMenu()
        menu.addItem(mi(up ? "● Connected to VPN" : "○ Disconnected"))
        if up { menu.addItem(mi("   down \(human(rx))   up \(human(tx))")) }
        menu.addItem(.separator())
        menu.addItem(mi("Server"))
        menu.addItem(mi("   load     \(load)"))
        menu.addItem(mi("   conns    \(conns)"))
        menu.addItem(mi("   latency  \(lat)"))
        menu.addItem(.separator())
        menu.addItem(mi(up ? "Disconnect" : "Connect", #selector(toggleVPN)))
        menu.addItem(mi("Refresh", #selector(refresh), "r"))
        menu.addItem(mi("Quit", #selector(NSApplication.terminate(_:)), "q"))
        item.menu = menu
    }

    @objc func toggleVPN() {
        let isUp = sh("sudo wg show \(WG_IFACE)").contains("interface")
        _ = sh("sudo wg-quick \(isUp ? "down" : "up") \(WG_IFACE)")
        refresh()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no dock icon
let delegate = App()
app.delegate = delegate
app.run()
