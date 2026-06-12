# Creating the server

> The one part of ColdVPN that isn't scripted — spinning up the Ubuntu VM that
> `setup.sh` later runs on. It happens by hand in your cloud provider's console,
> because there's no server to automate against yet.

ColdVPN needs a small, always-on Linux box to act as the VPN exit node.
[Oracle Cloud's **Always Free** tier](https://www.oracle.com/cloud/free/) is a
good fit (a free 24/7 VM), but any Ubuntu VPS works the same way.

## The pieces you create (and how they nest)

Creating an instance in Oracle also creates the network around it. Think of the
**VCN** as a private MAN, the **subnet** as a LAN inside it, and the **VM** as one
host on that LAN. The only thing you usually add by hand is the **ingress rule**.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#0f172a','primaryTextColor':'#e5e7eb','primaryBorderColor':'#475569','lineColor':'#94a3b8','fontSize':'14px'},'flowchart':{'padding':22,'nodeSpacing':55,'rankSpacing':70}}}%%
flowchart TB
    NET["INTERNET"]

    subgraph ORACLE["ORACLE — the host"]
        direction TB
        EDGE["ens3 · public NIC<br/>Public IP: server-ip<br/>edge 1:1 NAT ⇄ 10.0.0.x"]

        subgraph VCN["VCN — your cloud network (like a MAN)"]
            direction TB
            subgraph SUB["Subnet 10.0.0.0/24 — like a LAN<br/>Security List: ingress UDP 443 ← you add this"]
                direction TB
                subgraph VM["VM — private IP 10.0.0.x"]
                    direction TB
                    WG["wireguard process<br/>tunnel IP 10.8.0.2"]
                end
            end
        end
    end

    NET -->|"in · UDP 443"| EDGE
    EDGE ==>|"NAT in → drills to the VM"| WG
    WG ==>|"out · same ens3 + NAT"| EDGE
    EDGE -->|"out · to the internet"| NET

    style ORACLE fill:none,stroke:#94a3b8,stroke-width:2px,color:#cbd5e1
    style VCN fill:none,stroke:#8b5cf6,stroke-width:2px,color:#8b5cf6
    style SUB fill:none,stroke:#3b82f6,stroke-width:1.5px,color:#3b82f6
    style VM fill:none,stroke:#22c55e,stroke-width:1.5px,color:#22c55e
    style WG fill:none,stroke:#f59e0b,stroke-width:1.5px,color:#fde68a
```

`setup.sh` later runs *inside* the VM and uses both addresses: the **public IP**
is how clients reach it, and the **private `ens3` IP** is what NAT masquerades
traffic to on the way out. ([full packet path](../client/PACKET-FLOW.md))

---

## 1. Make an account
Sign up at **oracle.com/cloud/free**. Always Free resources don't expire.
(A card is needed for identity verification; Always Free shapes aren't charged.)

## 2. Create the instance
Console → **Compute → Instances → Create instance**:

- **Image** — Ubuntu 22.04
- **Shape** — an **Always Free-eligible** one (e.g. `VM.Standard.A1.Flex`)
- **SSH keys** — paste your *public* key (`~/.ssh/id_ed25519.pub`) so you can log in
- Create, then note the **public IP** it's assigned.

## 3. Open the WireGuard port
WireGuard here listens on **UDP 443**. Open it on the instance's subnet:

Console → **Networking → Virtual Cloud Networks → (your VCN) → Security Lists →
Default Security List → Add Ingress Rule**

- Source CIDR — `0.0.0.0/0`
- IP Protocol — **UDP**
- Destination Port — **443**

> The VCN and subnet are created automatically with the instance — usually you
> only add this one ingress rule.

That's the whole manual part. Now run **`./install.sh` on your Mac** — it SSHes
into this box and sets WireGuard up for you. ([README](../README.md))
