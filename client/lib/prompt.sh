#!/bin/bash
# client/lib/prompt.sh — interactive prompt helper for the ColdVPN installer.
#
# ask(): shows a default as grey "ghost" text you can accept with Enter or type
# over. Stray keys (Tab, arrows, other control chars) are ignored so the hint
# never vanishes; the ghost clears only when you type a real character, and
# comes back if you backspace to empty.
#
# It's hand-rolled with raw char-by-char reads instead of bash 4's `read -e -i`
# so it runs on macOS's stock bash 3.2 — no Homebrew bash dependency. See
# client/decisions/07-bash-3.2-not-homebrew.md for the why.

# Fallbacks so this is safe to source even if the caller didn't define colors.
: "${BLD:=}"; : "${DIM:=}"; : "${RST:=}"

# Usage: ask VAR "Question" "default"
ask() {
    local var=$1 question=$2 default=$3 input="" ch junk
    printf "\n  ${BLD}%s${RST}: " "$question"
    _draw_ghost() { [ -n "$default" ] && { printf '\033[s'; printf "${DIM}%s${RST}" "$default"; printf '\033[u'; }; }
    _draw_ghost
    while IFS= read -rsn1 ch; do
        case "$ch" in
            '')                                          # Enter → accept
                [ -z "$input" ] && [ -n "$default" ] && printf "\033[K%s" "$default"
                break ;;
            $'\033') read -rsn2 -t 1 junk 2>/dev/null ;; # ESC: swallow arrow-key sequence, ignore
            $'\t')   : ;;                                # Tab: ignore (ghost stays)
            $'\177'|$'\b')                               # backspace
                if [ -n "$input" ]; then
                    input="${input%?}"; printf '\b \b'
                    [ -z "$input" ] && { printf '\033[K'; _draw_ghost; }   # empty again → ghost back
                fi ;;
            [[:print:]])                                 # a real printable char
                [ -z "$input" ] && printf '\033[K'       # first real char wipes the ghost
                input+="$ch"; printf '%s' "$ch" ;;
            *) : ;;                                       # any other control char: ignore
        esac
    done
    printf '\n'
    eval "$var=\"${input:-$default}\""
}
