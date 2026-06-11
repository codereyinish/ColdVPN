# Decision: resolve DNS *through* the tunnel (via the VPS), not direct to Cloudflare

We set `DNS = 1.1.1.1` in the client config, but the query does **not** go
straight to Cloudflare. It rides the encrypted tunnel to our VPS first, and the
VPS forwards it on. Cloudflare is the **resolver**; the VPS is the **courier**.

```
Safari → [encrypted tunnel] → VPS → [plain DNS :53] → Cloudflare (1.1.1.1)
              leg 1                       leg 2
        nobody sees inside        query is Cloudflare-bound,
                                  but sourced from the VPS, not you
```

This is a deliberate choice. Sending DNS direct (outside the tunnel) would be
simpler and a hair faster — but it reopens the single most common VPN leak.

## Why not direct: the DNS leak

Web traffic is already double-protected (HTTPS + the tunnel), so an eavesdropper
on the local network can't read the *pages*. But the **DNS query names the domain
in cleartext** — it's the one part that says "he's visiting example.com." If DNS
went direct, that query would leak around the tunnel:

```
page content    → hidden (HTTPS) + hidden (tunnel)        ok
DNS query direct → "he's looking up example.com"          leak — the one thing that matters
```

A VPN is only as good as its **leakiest** path. The moment one category of
traffic (DNS, IPv6, anything) slips around the tunnel, that's where you get
fingerprinted. So we funnel everything — DNS included — through the VPS.

## Consequences if we got this wrong (direct DNS)

| Risk | Direct to Cloudflare | Through the tunnel (our choice) |
|---|---|---|
| **Privacy** | Local Wi-Fi / ISP sees every domain you resolve | They see only an encrypted blob to the VPS |
| **Tampering** | An untrusted network can spoof a reply and redirect you (DNS poisoning) | The query can't be touched in transit on leg 1 |
| **Identity** | Your real IP is the source of every lookup | Lookups are sourced from the VPS, not you |

## The leg-2 question: can it still be tampered with?

Yes — leg 2 (VPS → Cloudflare) is ordinary DNS, which has **no built-in auth or
encryption**. A man-in-the-middle there *could* forge "example.com is at 6.6.6.6"
(an attacker's server). DNS alone does not stop this.

### How certificates resolve it (one layer down, at TLS)

A forged DNS answer only changes **where** you connect, not **who** can prove
their identity. That proof happens in the TLS handshake *after* DNS:

```
1. DNS (poisoned)  → "example.com is at 6.6.6.6"   (attacker's box)
2. Safari connects to 6.6.6.6, starts HTTPS
3. TLS: "prove you're example.com"
4. Server must present a CERTIFICATE for example.com, signed by a trusted CA
5. Attacker can't — no CA signs example.com for someone who doesn't control it,
   and they lack example.com's private key
6. Safari rejects: "certificate not valid" → refuses to load
```

So the **certificate is the backstop**: DNS hands you an address, the certificate
proves the address isn't lying. The worst a DNS tamper can do is **denial** (cert
error, can't reach the site) — not silent **impersonation**. The dangerous
exception is plain-HTTP sites with no cert to check; another reason HTTPS-only
matters.

## What we're up to

- **Default (now):** `DNS = 1.1.1.1` resolved through the tunnel. The VPS is the
  courier, Cloudflare answers. This kills the local-network DNS leak — the
  realistic threat on public/free Wi-Fi — and decouples lookups from your IP.
- **The one party who sees queries in cleartext is the VPS itself** — which is
  *our* server, so that's acceptable (it's us).
- **Optional hardening of leg 2**, if we want the VPS→resolver hop sealed too:
  - **DoH / DoT** — wrap DNS in TLS so leg 2 is encrypted + authenticated (uses
    the same certificate machinery as HTTPS).
  - **DNSSEC** — cryptographic signatures on the records themselves, so a forged
    answer is detected at the DNS layer (a signature chain, not TLS certs).
  - **Run a resolver on the VPS** (`unbound`/`dnsmasq`) and set `DNS = 10.8.0.1`
    (the VPS's tunnel IP) — then nothing leaves the VPS for DNS at all.

## Decision

Route DNS through the tunnel via the VPS. Standard VPN hygiene, closes the most
common leak, costs one extra hop. Leg-2 encryption (DoH) and on-VPS resolving are
noted as future hardening, not required for the core privacy goal.
