# Body of the client setup script (macOS and Linux). Don't run this file
# directly: ./rdesk client-setup prepends SERVER_IP, SERVER_KEY and RD_PASSWORD.
#
# Installs RustDesk (if missing), points it at the private server and enables
# unattended access with a permanent password. On Linux it also switches to
# Xorg when available and disables sleep; on macOS it disables sleep and opens
# the privacy settings RustDesk needs.
set -euo pipefail

: "${SERVER_IP:?}" "${SERVER_KEY:?}" "${RD_PASSWORD:?}"

# Launched from a file manager ("Run as a Program") there's no terminal to show
# progress or ask for a password, so reopen in one.
if [ ! -t 0 ] && [ -z "${RD_IN_TERMINAL:-}" ] && [ "$(uname -s)" = Linux ]; then
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  export RD_IN_TERMINAL=1
  for term in gnome-terminal konsole xfce4-terminal mate-terminal x-terminal-emulator xterm; do
    command -v "$term" >/dev/null || continue
    case "$term" in
      gnome-terminal|mate-terminal) exec "$term" -- bash "$self" ;;
      xfce4-terminal) exec "$term" -x bash "$self" ;;
      *) exec "$term" -e bash "$self" ;;
    esac
  done
fi

# Keep a window we opened (or a double-clicked .command) open to show the result.
if [ -n "${RD_IN_TERMINAL:-}" ] || [ "${0##*.}" = command ]; then
  trap 'printf "\nPress Enter to close this window..."; read -r _' EXIT
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user (without sudo); it will ask for your password." >&2
  exit 1
fi

step() { printf '\n==> %s\n' "$*"; }
die() { echo "$*" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *) die "Unsupported CPU: $(uname -m)" ;;
esac

# Print the download URL of the latest release asset matching an ERE suffix,
# e.g. "-x86_64\.deb".
latest_asset() {
  curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
    | grep -o "\"browser_download_url\": *\"[^\"]*/rustdesk-[0-9.]*$1\"" \
    | head -n1 | sed -E 's/.*"(https:[^"]*)"$/\1/'
}

download() {
  local url
  url="$(latest_asset "$1")"
  [ -n "$url" ] || die "Couldn't find a RustDesk download for this computer."
  curl -fL --progress-bar -o "$2" "$url"
}

# Point RustDesk at the server and set the password. $1 is the rustdesk binary.
configure() {
  sudo "$1" --option custom-rendezvous-server "$SERVER_IP"
  sudo "$1" --option relay-server "$SERVER_IP"
  sudo "$1" --option key "$SERVER_KEY"
  sudo "$1" --password "$RD_PASSWORD"
}

finish() {
  local id
  id="$(sudo "$1" --get-id 2>/dev/null || true)"
  printf '\nAll done!\n'
  [ -n "$id" ] && printf 'Your RustDesk ID is: %s  (tell this number to the person helping you)\n' "$id"
}

install_linux() {
  local pkg tmp
  step "Downloading and installing the latest RustDesk"
  tmp="$(mktemp -d)"
  if command -v apt-get >/dev/null; then
    pkg="$tmp/rustdesk.deb"; download "-${ARCH}\.deb" "$pkg"
    sudo apt-get install -y "$pkg"
  elif command -v dnf >/dev/null; then
    pkg="$tmp/rustdesk.rpm"; download "-0\.${ARCH}\.rpm" "$pkg"
    sudo dnf install -y "$pkg"
  elif command -v zypper >/dev/null; then
    pkg="$tmp/rustdesk.rpm"; download "-0\.${ARCH}-suse\.rpm" "$pkg"
    sudo zypper --non-interactive install --allow-unsigned-rpm "$pkg"
  else
    die "Unsupported Linux distribution (needs apt, dnf or zypper)."
  fi
  rm -rf "$tmp"
}

setup_linux() {
  local gdm="" f

  step "Asking for your password (needed to install software)"
  sudo -v

  if command -v rustdesk >/dev/null; then
    step "RustDesk is already installed"
  else
    install_linux
  fi

  step "Starting the RustDesk background service"
  sudo systemctl enable --now rustdesk
  sleep 3

  step "Connecting RustDesk to the private server"
  configure rustdesk
  sudo systemctl restart rustdesk

  # RustDesk can't reliably control the mouse on Wayland. Newer distros
  # (e.g. Ubuntu 25.10+) no longer ship an Xorg session, so only switch when
  # one is installed.
  for f in /etc/gdm3/custom.conf /etc/gdm/custom.conf; do [ -f "$f" ] && gdm="$f" && break; done
  if [ -n "$gdm" ] && ls /usr/share/xsessions/*.desktop >/dev/null 2>&1; then
    step "Switching the login screen to Xorg (needed for remote control)"
    if grep -qE '^\s*#?\s*WaylandEnable=' "$gdm"; then
      sudo sed -i -E 's/^\s*#?\s*WaylandEnable=.*/WaylandEnable=false/' "$gdm"
    else
      sudo sed -i '/^\[daemon\]/a WaylandEnable=false' "$gdm"
    fi
  elif [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
    step "Note: this system only has Wayland; you may need to approve a screen-sharing prompt when someone connects"
  fi

  if command -v gsettings >/dev/null &&
     gsettings list-schemas 2>/dev/null | grep -qx org.gnome.settings-daemon.plugins.power; then
    step "Turning off screen blanking and automatic suspend"
    gsettings set org.gnome.desktop.session idle-delay 0
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
  else
    step "Note: turn off automatic suspend in your desktop's power settings"
  fi

  finish rustdesk
  echo "Please restart the computer now so the changes take effect."
}

MAC_APP=/Applications/RustDesk.app
MAC_BIN="$MAC_APP/Contents/MacOS/RustDesk"

install_macos() {
  local tmp mnt
  step "Downloading and installing the latest RustDesk"
  tmp="$(mktemp -d)"
  mnt="$tmp/mnt"
  download "-${ARCH}\.dmg" "$tmp/rustdesk.dmg"
  hdiutil attach -nobrowse -quiet -mountpoint "$mnt" "$tmp/rustdesk.dmg"
  sudo cp -R "$mnt/RustDesk.app" /Applications/
  hdiutil detach -quiet "$mnt"
  rm -rf "$tmp"
}

setup_macos() {
  step "Asking for your password (needed to install software)"
  sudo -v

  if [ -x "$MAC_BIN" ]; then
    step "RustDesk is already installed"
  else
    install_macos
  fi

  step "Starting RustDesk"
  open -a "$MAC_APP"
  sleep 5

  step "Connecting RustDesk to the private server"
  configure "$MAC_BIN"

  step "Preventing the Mac from going to sleep"
  sudo pmset -a sleep 0

  finish "$MAC_BIN"
  cat <<'EOF'

One last thing, which macOS only allows you to do by hand. Two settings
windows will open. In each one, turn ON the switch next to RustDesk
(click + and pick RustDesk from Applications if it isn't listed):

  1. Accessibility       (lets the helper control the mouse and keyboard)
  2. Screen Recording    (lets the helper see the screen)

If RustDesk asks to install or start its service, click Install/Start.
EOF
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  sleep 1
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
}

case "$(uname -s)" in
  Linux) setup_linux ;;
  Darwin) setup_macos ;;
  *) die "Unsupported system: $(uname -s)" ;;
esac
