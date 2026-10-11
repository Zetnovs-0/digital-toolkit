#!/usr/bin/env bash
# ---------------------------------------------------------------
# fetch_logos.sh — download every logo and regenerate manifest.js
#
# Usage:   bash fetch_logos.sh
# Env:     SI_MIRROR   simple-icons base URL  (default: jsdelivr)
#          CURLFLAGS   extra curl args        (default: "-fsSL --max-time 15")
#
# Per name, tries in order:
#   1. simple-icons SVG (comma-separated slug candidates), tinted
#      with the brand color from the COLORS table below
#   2. direct URL (4th column of the table, if set)
#   3. DuckDuckGo favicon (domain)
#   4. Google favicon PNG @256 (domain)
# Only HTTP-200 downloads with a real image signature are kept;
# anything else stays out of manifest.js and falls back to the
# CDN chain inside index.html.
# ---------------------------------------------------------------
set -u
cd "$(dirname "$0")"

SI_MIRROR="${SI_MIRROR:-https://cdn.jsdelivr.net/npm/simple-icons@latest/icons}"
CURLFLAGS="${CURLFLAGS:--fsSL --max-time 15}"

# Only trust HTTP 200 with a non-empty body (favicon services return
# placeholder images alongside 404 codes — never accept those).
fetch() {
  local code
  code=$(curl $CURLFLAGS -o "$2" -w "%{http_code}" "$1" 2>/dev/null)
  [ "$code" = "200" ] && [ -s "$2" ]
}
is_svg()    { head -c 100 "$1" 2>/dev/null | grep -aqi "<svg\|<?xml"; }
pick_ext()  { # inspect magic bytes -> png|gif|ico|jpg
  od -An -tx1 -N4 "$1" 2>/dev/null | grep -qi "89 50 4e 47" && { echo png;  return; }
  od -An -tx1 -N4 "$1" 2>/dev/null | grep -qi "47 49 46 38" && { echo gif;  return; }
  od -An -tx1 -N4 "$1" 2>/dev/null | grep -qi "00 00 01 00" && { echo ico;  return; }
  od -An -tx1 -N2 "$1" 2>/dev/null | grep -qi "ff d8"       && { echo jpg;  return; }
  echo png
}
save_raster() { # $1=tmp file, $2=target path without extension -> prints final name
  local ext; ext="$(pick_ext "$1")"; mv "$1" "$2.$ext"; echo "$2.$ext"
}
slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//'; }

# Simple Icons SVGs ship monochrome black; tint them with brand colors.
# (simple-icons dropped some Microsoft/etc. icons from its metadata, so a
#  few hexes are hardcoded from the brands' own sites.)
declare -A COLORS=(
  [zenbrowser]=F76F53 [firefox]=FF7139 [librewolf]=00ACFF [brave]=FB542B
  [googlechrome]=4285F4 [vivaldi]=EF3939 [safari]=006CFF [deepseek]=4D6BFE
  [googlegemini]=8E75B2 [googletranslate]=4285F4 [deepl]=0F2B46 [gmail]=EA4335
  [tuta]=850122 [discord]=5865F2 [whatsapp]=25D366 [cobalt]=000000
  [qbittorrent]=2F67BA [googlemaps]=4285F4 [organicmaps]=006C35
  [openstreetmap]=7EBC6F [soundcloud]=FF5500 [7zip]=000000 [sharex]=2885F1
  [libreoffice]=18A303 [davinciresolve]=233A51 [audacity]=0000CC
  [ublockorigin]=800000 [bitwarden]=175DDC [darkreader]=141E24
  [internetarchive]=666666 [mullvad]=294D73 [microsoftedge]=0078D7
  [opera]=FF1B2D [gnome]=4A86CF [qt]=41CD52 [windows]=0078D4 [apple]=000000
  [linuxmint]=86BE43 [ubuntu]=E95420 [popos]=48B9C7 [debian]=A81D33
  [fedora]=51A2DA [archlinux]=1793D1 [cachyos]=2DD4BF [nixos]=5277C3
)
colorize() { # $1 = svg file, $2 = slug
  local hex="${COLORS[$2]:-}"
  [ -n "$hex" ] && sed -i "0,/<svg /s//<svg fill=\"#${hex}\" /" "$1"
}

# name | simple-icons slug candidates (comma-sep, empty = skip) | fallback domain | direct URL
ITEMS=$(cat <<'EOF'
Zen|zenbrowser|zen-browser.app|
Helium||helium.computer|
Firefox|firefox|mozilla.org|
LibreWolf|librewolf|librewolf.net|
Brave|brave|brave.com|
Google Chrome|googlechrome|google.com|
Vivaldi|vivaldi|vivaldi.com|
Safari|safari|apple.com|
DeepSeek|deepseek|deepseek.com|
Gemini|googlegemini|gemini.google.com|
Google Translate|googletranslate|translate.google.com|
DeepL|deepl|deepl.com|
Reverso||reverso.net|
Gmail|gmail|mail.google.com|
TutaMail|tuta|tuta.com|
Equibop|discord|equicord.org|
ZapZap|whatsapp|whatsapp.com|
Hiddify|hiddify|hiddify.com|
Cobalt|cobalt|cobalt.tools|
qBittorrent|qbittorrent|qbittorrent.org|
XMCL||xmcl.app|https://github.com/xmcl.png
Prism Launcher|prismlauncher|prismlauncher.org|
Windy||windy.com|
Google Maps|googlemaps|maps.google.com|
Organic Maps|organicmaps|organicmaps.app|
OpenStreetMap|openstreetmap|openstreetmap.org|
SoundCloud|soundcloud|soundcloud.com|
Radio Garden||radio.garden|
7-Zip|7zip|7-zip.org|
ShareX|sharex|getsharex.com|
PowerToys|powertoys|microsoft.com|
balenaEtcher|balenaetcher,balena|balena.io|
Clonezilla|clonezilla|clonezilla.org|https://clonezilla.org/images/clonezilla_logo_transparent.gif
Flameshot|flameshot|flameshot.org|
LibreOffice|libreoffice|libreoffice.org|
DaVinci Resolve|davinciresolve|blackmagicdesign.com|
Audacity|audacity|audacityteam.org|
uBlock Origin|ublockorigin|ublockorigin.com|
Bitwarden|bitwarden|bitwarden.com|
Dark Reader|darkreader|darkreader.org|
Wayback Machine|internetarchive|archive.org|
Mullvad Browser|mullvad|mullvad.net|
Waterfox|waterfox|waterfox.net|
Chromium|chromium|chromium.org|
Microsoft Edge|microsoftedge|microsoft.com|
Opera|opera|opera.com|
GNOME Web|gnome|gnome.org|
Falkon|falkon|falkon.org|
qutebrowser|qt|qutebrowser.org|
Ladybird|ladybird|ladybird.org|
Windows 11|windows|microsoft.com|
macOS|apple|apple.com|
Linux Mint|linuxmint|linuxmint.com|
Ubuntu|ubuntu|ubuntu.com|
Pop!_OS|popos|pop.system76.com|
Debian|debian|debian.org|
Fedora|fedora|fedoraproject.org|
Arch Linux|archlinux|archlinux.org|
CachyOS|cachyos|cachyos.org|
NixOS|nixos|nixos.org|
EOF
)

declare -A MAP
fail=()
okn=0

while IFS='|' read -r name slugs domain direct; do
  [ -z "$name" ] && continue
  file="$(slugify "$name")"
  got=""

  # 1. simple-icons SVGs (try each slug candidate)
  if [ -n "$slugs" ]; then
    IFS=',' read -ra sl <<< "$slugs"
    for s in "${sl[@]}"; do
      if fetch "$SI_MIRROR/$s.svg" "$file.svg.tmp" && is_svg "$file.svg.tmp"; then
        mv "$file.svg.tmp" "$file.svg"
        colorize "$file.svg" "$s"
        got="$file.svg"; break
      fi
      rm -f "$file.svg.tmp"
    done
  fi

  # 2. Direct URL (hand-picked official asset)
  if [ -z "$got" ] && [ -n "$direct" ]; then
    if fetch "$direct" "$file.img.tmp" && is_svg "$file.img.tmp"; then
      mv "$file.img.tmp" "$file.svg"; got="$file.svg"
    elif [ -f "$file.img.tmp" ] && [ -s "$file.img.tmp" ]; then
      got="$(save_raster "$file.img.tmp" "$file")"
    fi
    rm -f "$file.img.tmp"
  fi

  # 3. DuckDuckGo favicon
  if [ -z "$got" ] && [ -n "$domain" ]; then
    if fetch "https://icons.duckduckgo.com/ip3/$domain.ico" "$file.img.tmp"; then
      got="$(save_raster "$file.img.tmp" "$file")"
    fi
    rm -f "$file.img.tmp"
  fi

  # 4. Google favicon
  if [ -z "$got" ] && [ -n "$domain" ]; then
    if fetch "https://www.google.com/s2/favicons?domain=$domain&sz=256" "$file.img.tmp"; then
      got="$(save_raster "$file.img.tmp" "$file")"
    fi
    rm -f "$file.img.tmp"
  fi

  if [ -n "$got" ]; then
    MAP["$name"]="$got"; okn=$((okn+1))
    printf '  ok    %-18s -> %s\n' "$name" "$got"
  else
    fail+=("$name"); printf '  FAIL  %-18s (no source worked)\n' "$name"
  fi
done <<< "$ITEMS"

# Regenerate manifest.js
{
  echo "/* Auto-generated by fetch_logos.sh — maps tool names to files in this folder. */"
  echo "/* Replace any file with your own anytime, then bump the version below.      */"
  echo "window.LOCAL_LOGOS_MANIFEST = {"
  echo "  version: 1,"
  echo "  logos: {"
  for name in "${!MAP[@]}"; do
    printf '    "%s": "%s",\n' "$name" "${MAP[$name]}"
  done
  echo "  },"
  echo "};"
} > manifest.js

echo
echo "Downloaded: $okn / $(echo "$ITEMS" | grep -c . )   manifest.js entries: ${#MAP[@]}"
[ ${#fail[@]} -gt 0 ] && echo "Failed (will use CDN fallback): ${fail[*]}"
exit 0
