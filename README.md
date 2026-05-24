# Claude Code Statusline

> A live, color-coded status bar for [Claude Code](https://claude.ai/code) on Windows — showing your active model, session usage, context window, and time until reset at a glance.

---

## What it looks like

![Claude Code Statusline preview](assets/preview.png)

The bar updates live with every message you send. When limits get critical:

```
  🤖 Claude Opus 4.7   │   ⚡ ##------ 28%   │   ⏳ reset 47m
  🧠 ##------ 22% (44k)   │   ⚠️  compact soon
```

---

## What each indicator means

| Indicator | Description |
|-----------|-------------|
| 🤖 **Model** | The Claude model currently active in your session |
| ⚡ **Session bar** | Remaining capacity in your 5-hour usage window |
| ⏳ **Reset countdown** | Time until your 5-hour window resets |
| 🧠 **Context bar** | Remaining context window space, with token count |
| ⚠️ **Compact warning** | Appears when context is >80% full |
| 📅 **Weekly bar** | Appears only when your 7-day usage is >80% |

**Bar colors:**
- 🟢 Green — more than 60% remaining
- 🟡 Yellow — 30–60% remaining
- 🔴 Red — less than 30% remaining

---

## Requirements

- Windows 10 or 11
- [Claude Code](https://claude.ai/code) installed
- PowerShell 5.1 (built into Windows — no extra installs needed)

---

## Quick Install / Uninstall

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main/setup.ps1 | iex
```

If [Node.js 18+](https://nodejs.org) is available, the interactive wizard launches automatically. Otherwise a simpler PowerShell menu is used — both produce the same result.

Choose **[1] Install**, walk through the steps, and restart Claude Code when done.

To reconfigure at any time, re-run and choose **[1] Install** again — your previous settings are pre-filled.

---

## Manual Install

1. Clone the repository:

   ```powershell
   git clone https://github.com/LucieFairePy/Claude-Code-StatusLine.git
   cd Claude-Code-StatusLine
   ```

2. Run the setup script:

   ```powershell
   .\setup.ps1
   ```

   If [Node.js 18+](https://nodejs.org) is available, the interactive wizard launches automatically. Otherwise a simpler PowerShell menu is used — both produce the same result.

3. Choose **[1] Install** and restart Claude Code.

---

## How it works

Claude Code supports a custom `statusLine` command in `~/.claude/settings.json`. When configured, Claude Code pipes a JSON payload to your command after every exchange — containing model info, token counts, rate limit stats, and timing data.

This project provides:

- **`statusline-wrapper.ps1`** — A self-contained PowerShell script that reads the JSON, formats your configured layout into colored lines, and prints them to stdout. No external dependencies — pure PowerShell 5.1.
- **`statusline-config.json`** — Your saved preferences (which indicators to show, their order, layout, bar width, thresholds). Generated during install.

The installer patches `~/.claude/settings.json` to register the wrapper:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -NonInteractive -File \"C:\\Users\\<you>\\.claude\\statusline-wrapper.ps1\""
  }
}
```

---

## Customization

Re-run the setup script and choose **[1] Install** — the full wizard runs before anything is changed.

### Setup wizard (Node.js)

The wizard walks you through four steps, with a live preview that updates as you configure:

**Step 1 — Features**  
Toggle each indicator on or off with Space, confirm with Enter.

**Step 2 — Visibility thresholds**  
Choose when the Weekly bar and Compact warning appear: always, or only from 50 / 60 / 70 / 80 / 90% usage.

**Step 3 — Layout**  
Choose 1, 2, or 3 lines. For each line, pick features one at a time — **the order you pick is the order they display**. Remaining features fill the next line automatically.

```
  Line 1 — first feature:
  ❯ 🤖  Model name
    ⚡  Session usage  (5h)
    ⏳  Reset countdown
    🧠  Context window
    ✓  Done — confirm line 1
```

**Step 4 — Bar width**  
Choose between 6, 8, 10, or 12 character wide progress bars.

### PowerShell fallback menu

When Node.js is not available, a keyboard-driven menu is shown instead. Features are the same:

- **[1]–[6]** toggle individual indicators
- **[7] / [8]** cycle visibility thresholds for Weekly and Compact
- **[9]** cycle bar width
- **[L]** open the layout menu — choose number of lines, then pick features in display order for each line
- **[N]** preview and apply

Your choices are saved to `~/.claude/statusline-config.json` and pre-filled next time you reconfigure.

---

## Troubleshooting

**Status bar doesn't appear after install**
- Restart Claude Code completely (close and reopen).
- Check that `~/.claude/settings.json` contains a `statusLine` key.

**All bars show `--------`**
- Normal on the very first message. The bar populates once Claude Code sends its first JSON payload.

**PowerShell execution policy error**
- Run: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## Uninstall

Re-run the setup script and choose **[2] Uninstall**:

```powershell
irm https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main/setup.ps1 | iex
```

---

## License

MIT — see [LICENSE](LICENSE).
