# SSH trust model: how I know I'm talking to the real server

Before ColdVPN automates anything over SSH (pushing the Mac's key to the server,
pulling the server's key back), I need to be sure that when I `ssh` to the server
I'm reaching *my* box — not a man-in-the-middle. This is that reasoning, traced as
a chain of doubts: each step raises a question, answers it, and the answer hands
me the next question.

---

**1 · I want to SSH into the server's public IP.**
🤔 But how do I even know this IP is the right one?
✅ I got it from the **Oracle console** — and I trust the console because it's
**HTTPS**: the certificate verifies the site is really `oracle.com`, not a fake.
So the IP I copied is genuine.
➡️ Okay, I've got a trusted IP — so let me connect to it…

**2 · I `ssh` into that public IP.**
🤔 But even with the right IP — can't someone still sit in the middle? Hacked
wifi, a sketchy free hotspot?
✅ Yes — a **MITM** can intercept the path. So the right IP alone isn't enough.
The question becomes: how does SSH itself protect me?
➡️ That's where the key exchange kicks in…

**3 · The server sends me its public key.**
🤔 I could just save this to `known_hosts` — but how do I know this public key
isn't fake/compromised?
✅ SSH makes the server solve a **puzzle** only its **private key** can solve.
*(Direction matters: the private key is the secret, and the public key is derived
**from** it — one-way. So only the real owner of the private key can solve it.)*
Puzzle solved → the sender genuinely **owns** this key pair.
➡️ Great, puzzle solved, so the key's legit… right?

**4 · Wait — not so fast.**
🤔 The attacker could generate their **own** private+public pair and solve their
**own** puzzle! So passing the puzzle only proves they own *some* key — not that
it's Oracle's key. How do I know this public key is really from my server?
✅ This is where step 1 comes back. I verify through the **trusted HTTPS channel**:
the Oracle console (cert-proven `oracle.com`) shows me the **genuine fingerprint**.
I compare it to the key I was handed — or better, I copy the real public **key**
from the console straight into `known_hosts` myself.
➡️ Now the genuine key is locked in. Let me trace it through…

**5 · Now, even if a MITM exists — what actually happens?**
🤔 The attacker knows the public key (it's public!). Can't they just impersonate?
✅ They can **present** the real public key — but they **can't solve the puzzle**
(no private key). And if they present their **own** key to pass the puzzle, it
**won't match** my `known_hosts`. Either way → **rejected**. So the connection only
completes with the real server, and its public key gets **saved to `known_hosts`.**
➡️ So next time I only have to compare against `known_hosts`…

**6 · Next connection.**
🤔 But couldn't it get intercepted next time too?
✅ Someone can try, but: (a) their key **won't match** `known_hosts` → SSH refuses
with a loud warning, and (b) the session is encrypted with **ephemeral keys** the
real handshake set up, so an interceptor **can't decrypt** it anyway. So — no
problem. *(And the puzzle re-runs at the start of **every** connection, not per
command.)*

---

## In one breath

> Trust the IP because **HTTPS** proves it's Oracle → but the network can still be
> MITM'd → so SSH makes the server **prove it owns its key** (the puzzle) → but
> anyone can own *a* key, so I **verify it's Oracle's key** via the HTTPS console
> (compare, or pre-paste into `known_hosts`) → after that, any impostor fails
> *either* the puzzle *or* the `known_hosts` match → the connection stays secure,
> every time.

## Two things that are easy to get backwards

- **Key direction:** the **private key comes first** (the secret); the **public
  key is derived from it**, one-way. You can't compute the private from the public
  — that one-wayness is *why* the puzzle is unforgeable.
- **You save the key, not the fingerprint:** `known_hosts` stores the full public
  **key**. The fingerprint is just a short hash, for eyeballing the comparison.

## Why this matters for ColdVPN

The weak moment is the **very first** connect (empty `known_hosts`, nothing to
compare). For a human that's "verify once via the console, then trust forever."
For **automation** (a script SSHing in), the temptation is to silence the
first-connect prompt by disabling host-key checking — which throws away this whole
protection. So any SSH automation here must **keep host-key checking on** and
**pre-seed the console-verified key** instead. That constraint is the starting
point for the next decision →
[**06 · automating the key handoff over SSH**](06-automate-key-handoff-over-ssh.md).
