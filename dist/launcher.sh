#!/bin/bash
# Daytona USA (recompiled) -- Linux / Steam Deck settings launcher.
#
# A small dialog for the daytona.ini options people actually change (render
# resolution, window size, fullscreen, vsync), then starts the game through
# run.sh. Lives beside run.sh and resolves its own directory. Needs zenity,
# which SteamOS and most desktops ship; without it this just starts the game.
# Arguments are passed through to the game.
#
# No refresh-rate option on purpose: the game paces itself off a fixed 60Hz
# tick, so changing it would change game speed (refresh_rate is ignored).
cd "$(dirname "$0")"
INI=daytona.ini

if ! command -v zenity >/dev/null 2>&1; then
  exec ./run.sh "$@"
fi

get() {   # get <key> <default>
  local v
  v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$INI" 2>/dev/null | head -1 | tr -d '\r')
  echo "${v:-$2}"
}
set_key() {   # set_key <key> <value> -- keys are unique across daytona.ini
  if grep -q "^[[:space:]]*$1[[:space:]]*=" "$INI" 2>/dev/null; then
    sed -i "s/^[[:space:]]*$1[[:space:]]*=.*/$1 = $2/" "$INI"
  fi
}
# zenity's combo boxes cannot preselect, so the current value goes first.
first() {   # first <current> <option>...
  local cur=$1; shift
  local out=$cur o
  for o in "$@"; do [ "$o" != "$cur" ] && out="$out|$o"; done
  echo "$out"
}

# Render resolution is internal_resolution_scale x 1280x720.
scale_to_res() {
  case "$1" in
    1|1.0) echo 1280x720 ;; 1.25) echo 1600x900 ;; 1.5) echo 1920x1080 ;;
    2|2.0) echo 2560x1440 ;; 2.5) echo 3200x1800 ;; 3|3.0) echo 3840x2160 ;;
    4|4.0) echo 5120x2880 ;; *) echo 1280x720 ;;
  esac
}
res_to_scale() {
  case "$1" in
    1280x720) echo 1 ;; 1600x900) echo 1.25 ;; 1920x1080) echo 1.5 ;;
    2560x1440) echo 2 ;; 3200x1800) echo 2.5 ;; 3840x2160) echo 3 ;;
    5120x2880) echo 4 ;; *) echo 1 ;;
  esac
}
yesno() { case "$1" in true|yes|on|1) echo Yes ;; *) echo No ;; esac; }
tf() { [ "$1" = Yes ] && echo true || echo false; }

cur_render=$(scale_to_res "$(get internal_resolution_scale 1)")
cur_window=$(get resolution 1280x720)
cur_full=$(yesno "$(get fullscreen false)")
cur_vsync=$(yesno "$(get vsync true)")

choice=$(zenity --forms --title="Daytona USA" --text="Settings (the game always runs at 60 fps)" \
  --ok-label="Play" --separator="|" \
  --add-combo="Render resolution" \
  --combo-values="$(first "$cur_render" 1280x720 1600x900 1920x1080 2560x1440 3200x1800 3840x2160)" \
  --add-combo="Window size" \
  --combo-values="$(first "$cur_window" 1280x720 1280x800 1600x900 1920x1080 2560x1440)" \
  --add-combo="Fullscreen" --combo-values="$(first "$cur_full" Yes No)" \
  --add-combo="VSync" --combo-values="$(first "$cur_vsync" Yes No)" 2>/dev/null) || exit 0

IFS='|' read -r render window full vsync <<< "$choice"
# An untouched combo comes back empty: keep the current value.
render=${render:-$cur_render}; window=${window:-$cur_window}
full=${full:-$cur_full}; vsync=${vsync:-$cur_vsync}

set_key internal_resolution_scale "$(res_to_scale "$render")"
set_key resolution "$window"
set_key fullscreen "$(tf "$full")"
set_key vsync "$(tf "$vsync")"

exec ./run.sh "$@"
