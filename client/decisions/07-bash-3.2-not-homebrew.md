# Decision: target stock bash 3.2 — don't require Homebrew bash

I wanted nicer prompts — a default that sits in the input line, editable, accept
with Enter. The clean way to do that is bash's `read -e -i`.

One catch: that needs **bash 4+**, and macOS ships only **bash 3.2** (Apple froze
it years ago — they won't ship the GPLv3-licensed bash 4+).

**Homebrew can install bash 5 — which would solve the prompt problem outright. So
why didn't we just use it?** Point the shebang at `/opt/homebrew/bin/bash` (or
re-exec into it), and `read -e -i` works immediately. The reason we *didn't* is
the consequences it drags in for a *first-run installer*:

- **It adds a prerequisite to the one thing whose job is to have none.**
  `install.sh` is the first command a user runs on a clean Mac. Requiring a
  non-default bash *before* it can even prompt is circular — and Homebrew doesn't
  install a newer bash by default anyway, so "use Homebrew bash" really means "go
  install yet another thing first."
- **The path isn't stable.** Homebrew bash is `/opt/homebrew/bin/bash` on Apple
  Silicon but `/usr/local/bin/bash` on Intel — a brittle, arch-specific shebang.
- **Re-exec adds a failure mode.** Detect-and-relaunch-under-another-bash is more
  moving parts that can break — all for a cosmetic prompt feature.
- **It breaks the promise:** "runs on a vanilla Mac, no setup." A VPN installer
  should just work on the bash every Mac already has.

So the fancy prompt isn't worth dragging a whole interpreter dependency into the
bootstrap.

**How we solved it:** build the interactivity by hand using only bash-3.2
features — raw `read -rsn1` character reads plus terminal escape codes — instead
of `read -e -i`. Same grey-ghost, accept-on-Enter feel, but it runs on stock
`/bin/bash` everywhere, zero dependencies. The cost is that we hand-handle keys
(Tab and arrows ignored, backspace, Enter), which is fiddlier code — so it lives
in its own file, [`client/lib/prompt.sh`](../lib/prompt.sh), out of the
installer's main flow.

---

## The decision
- Target **stock bash 3.2**; the installer's shebang stays `#!/bin/bash`.
- Do **not** require or re-exec into Homebrew bash just for a prompt nicety.
- Get the interactive ghost-default prompt from 3.2-only primitives, kept in
  `client/lib/prompt.sh`.

> Nicer prompt wanted `read -e -i` → that needs bash 4 → macOS only ships 3.2 →
> using Homebrew bash would add a dependency to a zero-dependency installer →
> so hand-roll the prompt with 3.2 features instead.
