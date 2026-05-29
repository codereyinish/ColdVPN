# Contributing

Thanks for your interest in contributing! Every script in this project
is plain bash — readable, tweakable, no black boxes.

Contributions are welcome for bug fixes, improvements, and new features.
By contributing, you agree your changes fall under the same
[Elastic License 2.0](LICENSE) as this project.

---

## Ways to contribute

- 🐛 **Report a bug** — something not working on your machine
- 💡 **Suggest a feature** — open an issue before building it
- 🔧 **Fix a bug** — find it, fix it, pull request
- 📖 **Improve docs** — README, DEVELOPER.md, script comments
- 🖥️ **Add platform support** — Intel Mac fixes, other Linux distros

---

## Reporting a bug

Open an [issue](https://github.com/codereyinish/wg-hotspot-mac/issues) and include:

- What you did
- What you expected
- What actually happened
- Mac model (Apple Silicon or Intel) + macOS version

```bash
# Helpful debug info to paste in your issue
sw_vers
uname -m
sudo wg show
cat /var/log/wireguard-hotspot.log | tail -20
```

---

## Making a pull request

### 1. Fork and clone

```bash
git clone https://github.com/YOUR_USERNAME/wg-hotspot-mac
cd wg-hotspot-mac
```

### 2. Create a branch

```bash
git checkout -b fix/what-you-fixed
# or
git checkout -b feat/what-you-added
```

### 3. Make your changes

Scripts live in `client/` or `server/` — edit them directly.
See [DEVELOPER.md](DEVELOPER.md) for how to run and test each one manually.

### 4. Test before submitting

```bash
# Test wg-stats
sudo cp client/wg-stats /usr/local/bin/wg-stats
wg-stats
wg-stats --bar

# Test wireguard-hotspot.sh
sudo cp client/wireguard-hotspot.sh /usr/local/bin/wireguard-hotspot.sh
sudo /usr/local/bin/wireguard-hotspot.sh
```

### 5. Commit clearly

```bash
git commit -m "fix: what you fixed and why"
git commit -m "feat: what you added and why"
```

### 6. Open a pull request

Include:
- What you changed
- Why you changed it
- How you tested it

---

## Guidelines

- **Keep scripts readable** — comments explain why, not just what
- **One change per PR** — easier to review and merge
- **Test on your machine** — confirm it works before submitting
- **No compiled binaries** — everything stays plain text scripts

---

## What not to contribute

- Changes that repackage or redistribute the software
- Dependencies that require accounts or paid services
- Platform-specific hacks without a clear fallback

---

Full manual setup guide → [DEVELOPER.md](DEVELOPER.md)
