# Decision: the WireGuard CLI, not the Mac App Store app

The obvious easy choice would have been the official **WireGuard app** from the
Mac App Store. And it's genuinely tempting: it ships a proper **Network Extension**
(the real macOS VPN API), a clean GUI, **On-Demand** auto-connect, native stats —
and a user would set it up by just **importing the `wg0.conf`** and clicking
connect. Zero terminal, nothing to script.

So why build ColdVPN on the `wireguard-tools` **CLI** (Homebrew) instead?

**Because ColdVPN is driven by scripts, not clicks.** Three pieces depend on that,
and none of them work with the app:

- **`install.sh` brings the tunnel up itself** — `wg-quick up`, after writing the
  config. The app would need a human to import the file and click connect.
- **The menu-bar toggle** runs `wg-quick up`/`down` and reads live state from
  `wg show`. The app runs its tunnel inside a **sandboxed Network Extension the
  shell can't see or control** — so there'd be no scriptable on/off and no 🟢/🔴
  status button at all.
- **Full `wg-quick` control** — the routing split, DNS, `PostUp` hooks — is CLI-only.

The app gives you a button *you* click; the CLI gives you something you can
*automate*. ColdVPN's whole point — one-command install, a scriptable toggle,
manual off-after-reboot — only exists on the CLI side.

There's even a flip side: the app's headline feature, **On-Demand auto-connect**, is
exactly what ColdVPN *doesn't* want — it's deliberately manual, off after every
reboot. So the app's biggest convenience cuts *against* the design.

```
WireGuard app          -> easiest for a human; sandboxed NE; click-only; not scriptable
wireguard-tools (CLI)  -> scriptable: powers install.sh, the toggle, and wg-show status
```

**Decision: CLI only.** The app is the right tool if you just want to click a
config into a GUI — but it can't be the backbone of an automated, toggle-driven,
manual VPN. That's the CLI's job. (The CLI also leaves room for a custom
client-plus-server monitor the sandboxed app could never expose — see
`client/coldvpn-monitor`.)
