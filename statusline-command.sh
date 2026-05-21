#!/usr/bin/env bash

# Ensure jq is findable on Windows (WinGet installs it here but PATH may not be refreshed yet)
if ! command -v jq >/dev/null 2>&1; then
  WINGET_LINKS="$LOCALAPPDATA/Microsoft/WinGet/Links"
  WINGET_LINKS_BASH=$(cygpath -u "$WINGET_LINKS" 2>/dev/null || echo "$WINGET_LINKS" | sed 's|\\|/|g; s|^\([A-Za-z]\):|/\L\1|')
  export PATH="$PATH:$WINGET_LINKS_BASH"
fi

# Read stdin with a timeout fallback
if [ -t 0 ]; then
  input="{}"
else
  input=$(cat 2>/dev/null || echo "{}")
fi

# ── helpers ──────────────────────────────────────────────────────────────────

make_bar() {
  local pct="$1" width=8
  local filled=$(echo "$pct $width" | awk '{n=int(($1/100)*$2+0.5); if(n>$2) n=$2; if(n<0) n=0; print n}')
  local empty=$((width - filled))
  local bar=""
  local f=0; while [ $f -lt $filled ]; do bar="${bar}#"; f=$((f+1)); done
  local e=0; while [ $e -lt $empty  ]; do bar="${bar}-"; e=$((e+1)); done
  printf "%s" "$bar"
}

bar_color() {
  local pct="$1"   # remaining %
  if   [ "$pct" -ge 60 ]; then printf "\033[32m"   # green
  elif [ "$pct" -ge 30 ]; then printf "\033[33m"   # yellow
  else                          printf "\033[31m"   # red
  fi
}

RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
MAGENTA="\033[35m"
BLUE="\033[34m"
WHITE="\033[37m"
YELLOW="\033[33m"
GREEN="\033[32m"
RED="\033[31m"

# ── extract fields ────────────────────────────────────────────────────────────

model=$(echo "$input"        | jq -r '.model.display_name // empty' 2>/dev/null)
[ -z "$model" ] && model="Claude"

ctx_used=$(echo "$input"     | jq -r '.context_window.used_percentage // empty')
ctx_rem=$(echo "$input"      | jq -r '.context_window.remaining_percentage // empty')
ctx_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
ctx_input=$(echo "$input"    | jq -r '.context_window.current_usage.input_tokens // empty')

five_pct=$(echo "$input"     | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input"     | jq -r '.rate_limits.seven_day.used_percentage // empty')

# ── countdown to session reset ────────────────────────────────────────────────

countdown=""
if [ -n "$five_resets_at" ]; then
  now=$(date +%s 2>/dev/null)
  if [ -n "$now" ]; then
    diff=$(( five_resets_at - now ))
    if [ "$diff" -le 0 ]; then
      countdown="now!"
    else
      h=$(( diff / 3600 ))
      m=$(( (diff % 3600) / 60 ))
      if [ "$h" -gt 0 ]; then
        countdown="${h}h ${m}m"
      else
        countdown="${m}m"
      fi
    fi
  fi
fi

# ── assemble lines ────────────────────────────────────────────────────────────

SEP="${DIM}│${RESET}"

# ── LINE 1 : model | 5-hour session usage | countdown to reset ───────────────

line1="  🤖 ${CYAN}${BOLD}${model}${RESET}"

if [ -n "$five_pct" ]; then
  five_left=$(echo "$five_pct" | awk '{printf "%.0f", 100 - $1}')
  col=$(bar_color "$five_left")
  bar=$(make_bar "$five_left")
  line1="${line1}  ${SEP}  ⚡ ${col}${bar} ${five_left}%${RESET}"
else
  line1="${line1}  ${SEP}  ⚡ ${DIM}--------${RESET}"
fi

if [ -n "$countdown" ]; then
  if [ "$countdown" = "now!" ]; then
    line1="${line1}  ${SEP}  ⏳ ${RED}${BOLD}reset now!${RESET}"
  else
    line1="${line1}  ${SEP}  ⏳ ${DIM}reset ${countdown}${RESET}"
  fi
fi

# ── LINE 2 : context window | compact warning | weekly usage ─────────────────

if [ -n "$ctx_used" ]; then
  ctx_used_int=$(printf "%.0f" "$ctx_used")
else
  ctx_used_int=0
fi
if [ -n "$ctx_rem" ]; then
  ctx_rem_int=$(printf "%.0f" "$ctx_rem")
else
  ctx_rem_int=100
fi
ctx_color=$(bar_color "$ctx_rem_int")
ctx_bar=$(make_bar "$ctx_rem_int")

if [ -n "$ctx_window_size" ] && [ -n "$ctx_input" ]; then
  ctx_remaining_tokens=$(echo "$ctx_window_size $ctx_input" | awk '{r=$1-$2; if(r<0) r=0; if(r>=1000) printf "%.0fk", r/1000; else printf "%d", r}')
  ctx_left=$((100 - ctx_used_int))
  ctx_color=$(bar_color "$ctx_left")
  ctx_bar=$(make_bar "$ctx_left")
  line2="  🧠 ${ctx_color}${ctx_bar} ${ctx_left}%${RESET} ${DIM}(${ctx_remaining_tokens})${RESET}"
else
  line2="  🧠 ${DIM}--------${RESET}"
fi

if [ -n "$ctx_used_int" ] && [ "$ctx_used_int" -ge 80 ]; then
  line2="${line2}  ${SEP}  ${YELLOW}${BOLD}⚠️  compact soon${RESET}"
fi

if [ -n "$week_pct" ]; then
  week_used_int=$(printf "%.0f" "$week_pct")
  week_left=$(echo "$week_pct" | awk '{printf "%.0f", 100 - $1}')
  if [ "$week_used_int" -ge 80 ]; then
    col=$(bar_color "$week_left")
    bar=$(make_bar "$week_left")
    line2="${line2}  ${SEP}  ${RED}${BOLD}📅 ${bar} ${week_left}%${RESET}"
  fi
fi

printf "%b\n%b\n" "$line1" "$line2"
