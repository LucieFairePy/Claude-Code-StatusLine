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

A menu appears — choose **[1] Install**, then customize which indicators to show and the bar width. Restart Claude Code when done.

To reconfigure at any time, re-run and choose **[1] Install** again — your previous toggles are pre-filled.

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

3. Choose **[1] Install** and restart Claude Code.

---

## How it works

Claude Code supports a custom `statusLine` command in `~/.claude/settings.json`. When configured, Claude Code pipes a JSON payload to your command after every exchange — containing model info, token counts, rate limit stats, and timing data.

This project provides:

- **`statusline-wrapper.ps1`** — A self-contained PowerShell script that reads the JSON, formats it into two colored lines, and prints them to stdout. No external dependencies — pure PowerShell 5.1.
- **`statusline-config.json`** — Your saved preferences (which indicators to show, bar width). Generated during install.

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

Re-run the setup script and choose **[1] Install** — the customization menu is shown before anything is changed:

```
  Customize your status bar:

    [1] [ON ] Session bar (5-hour usage)
    [2] [ON ] Reset countdown
    [3] [ON ] Context window bar
    [4] [ON ] Compact warning (>80% ctx)
    [5] [ON ] Weekly usage bar (>80%)
    [6] Bar width: 8

  Type a number to toggle, N to continue:
```

Type a number to toggle that option on/off. Option **[6]** cycles the bar width through 6 / 8 / 10 / 12 characters. Type **N** to save and continue installation.

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
