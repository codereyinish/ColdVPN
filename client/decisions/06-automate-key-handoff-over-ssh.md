# Decision: automate the key handoff over SSH — one step, without dropping the guardrail

I want setup as convenient as possible for a first-time developer — ideally
**one step** instead of copying keys between two machines by hand. So: let
`install.sh` SSH into the server itself, push the Mac's `[Peer]`, pull the server's
key back, write `wg0.conf`, restart wg. You give one thing — the server IP — and it
does the rest. Builds on [**05 · the SSH trust model**](05-ssh-trust-model.md).

But should a *program* be SSHing into my server at all?

**Isn't that the same as me doing it by hand?** The script uses my SSH key and runs
sudo on the server — exactly what I do manually. The SSH and the sudo are
**identical**: a program connecting with my key has the same authority and the same
risk as me typing it. So the SSHing itself adds nothing dangerous.

So if the connection is identical, where could a problem come from? **Only the
first-connect prompt.** Manually, SSH asks *"authenticity can't be established…
continue?"* and I eyeball it. A script can't sit at a prompt — so people silence it
with `StrictHostKeyChecking=no`. That throws away the host-key check from
[doc 05](05-ssh-trust-model.md) and lets the script connect to an impostor. The
danger isn't the SSH or the sudo — it's **disabling the fingerprint check to keep
automation quiet.** The line isn't "manual vs program," it's "did I keep host-key
checking on?"

**How we solved it:** keep checking ON, and remove the prompt's *cause* instead of
the check — **pre-seed** the console-verified server key into `known_hosts` first
([Option B, doc 05](05-ssh-trust-model.md)). On an existing Mac it's already there
from earlier manual connects, so it verifies silently with nothing to disable.

---

## The decision
- `install.sh` **may** drive the handoff over SSH (one "server IP" prompt) — same
  authority as doing it by hand, so no new risk on its own.
- It **must** keep host-key verification on, against a pre-seeded / already-trusted
  `known_hosts`. Convenience comes from killing the *prompt*, never the *check*.

> One step for the beginner → naive way silences the host-key prompt → that
> re-opens MITM → so keep the check on and pre-seed the key → convenient **and** safe.
