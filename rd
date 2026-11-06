#!/usr/bin/env bash
# rd - manage a self-hosted RustDesk server on AWS Lightsail.
#
#   ./rd setup          create the server (terraform apply)
#   ./rd destroy        delete the server and everything it costs money for
#   ./rd on             start the server and wait until RustDesk is reachable
#   ./rd off            stop the server
#   ./rd status         show state, IP and CPU burst capacity
#   ./rd key            print the server's public key
#   ./rd ssh [cmd]      ssh into the server
#   ./rd client-setup   build ready-to-send setup files (Windows, Linux, macOS)
#   ./rd autostop <minutes|off>
#                       power the server off after this many idle minutes
#
# Uses your normal AWS credentials (AWS_PROFILE, env vars or the default profile).
# AUTOSTOP_MINUTES (default 60) sets the idle limit installed by setup.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$ROOT/.rustdesk"
KEY_CACHE="$CACHE_DIR/server.pub"

die() { echo "$*" >&2; exit 1; }

tf() { terraform -chdir="$ROOT" "$@"; }

tf_output() {
  tf output -raw "$1" 2>/dev/null || die "No server found. Run './rd setup' first."
}

# Read once per run; every command except setup needs them.
load_outputs() {
  REGION="$(tf_output region)"
  INSTANCE="$(tf_output instance_name)"
  SERVER_IP="$(tf_output rustdesk_server_ip)"
}

lightsail() { aws lightsail --region "$REGION" --output text "$@"; }

state() { lightsail get-instance-state --instance-name "$INSTANCE" --query state.name; }
is_running() { [ "$(state)" = running ]; }
is_stopped() { [ "$(state)" = stopped ]; }

# Poll a command until it succeeds, printing a dot per attempt.
wait_for() {
  local what="$1" tries="$2"; shift 2
  printf 'Waiting for %s' "$what"
  for _ in $(seq 1 "$tries"); do
    if "$@" >/dev/null 2>&1; then echo " ok"; return 0; fi
    printf '.'; sleep 5
  done
  echo " timed out" >&2; return 1
}

port_open() { nc -z -w 3 "$1" "$2"; }

# SSH with short-lived credentials from Lightsail (same as the browser SSH
# button), so no key pair has to be downloaded or managed.
ssh_server() {
  local dir details rc=0
  is_running || die "Server is off; run './rd on' first."
  dir="$(mktemp -d)"
  details="$(aws lightsail --region "$REGION" --output json \
    get-instance-access-details --instance-name "$INSTANCE" --protocol ssh)"
  jq -r .accessDetails.privateKey <<<"$details" > "$dir/key"
  jq -r .accessDetails.certKey <<<"$details" > "$dir/key-cert.pub"
  chmod 600 "$dir/key"
  mkdir -p "$CACHE_DIR"
  ssh -i "$dir/key" -o CertificateFile="$dir/key-cert.pub" \
    -o UserKnownHostsFile="$CACHE_DIR/known_hosts" -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 "$(jq -r .accessDetails.username <<<"$details")@$SERVER_IP" "$@" || rc=$?
  rm -rf "$dir"
  return "$rc"
}

cmd_setup() {
  for bin in terraform aws jq nc ssh; do
    command -v "$bin" >/dev/null || die "Missing '$bin'. See Prerequisites in README.md."
  done
  aws sts get-caller-identity >/dev/null || die "AWS credentials not working. Run 'aws configure' or set AWS_PROFILE."
  tf init -input=false >/dev/null
  tf apply
  load_outputs
  rm -f "$KEY_CACHE"
  wait_for "RustDesk to finish installing (first boot takes a few minutes)" 120 port_open "$SERVER_IP" 21116
  echo
  echo "Server IP: $SERVER_IP"
  printf 'Key:       '; cmd_key
  cmd_autostop "${AUTOSTOP_MINUTES:-60}"
  echo
  echo "Next: './rd client-setup' for the computer you support, then './rd off' when you're done."
}

cmd_destroy() {
  load_outputs
  echo "This deletes '$INSTANCE' and its static IP in $REGION."
  echo "The server key is lost: every client must be reconfigured if you set up again."
  tf destroy
  rm -rf "$CACHE_DIR"
}

cmd_on() {
  local s
  s="$(state)"
  if [ "$s" != running ]; then
    if [ "$s" = stopping ]; then wait_for "previous stop to finish" 60 is_stopped; fi
    lightsail start-instance --instance-name "$INSTANCE" >/dev/null
    wait_for "instance to boot" 60 is_running
  fi
  wait_for "RustDesk on $SERVER_IP:21116" 60 port_open "$SERVER_IP" 21116
  echo "Server is up: $SERVER_IP"
}

cmd_off() {
  lightsail stop-instance --instance-name "$INSTANCE" >/dev/null
  echo "Stopping $INSTANCE (takes about a minute)."
}

cmd_status() {
  local now burst
  echo "State: $(state)"
  echo "IP:    $SERVER_IP"
  now="$(date -u +%s)"
  burst="$(lightsail get-instance-metric-data --instance-name "$INSTANCE" \
    --metric-name BurstCapacityPercentage --unit Percent --statistics Average \
    --period 300 --start-time "$((now - 3600))" --end-time "$now" \
    --query 'sort_by(metricData,&timestamp)[-1].average' 2>/dev/null || true)"
  if [ -n "$burst" ] && [ "$burst" != None ]; then
    printf 'Burst: %.0f%%\n' "$burst"
  else
    echo "Burst: no data in the last hour"
  fi
}

# The key never changes for the life of the server, so cache it and keep
# working while the server is off.
cmd_key() {
  if [ ! -s "$KEY_CACHE" ]; then
    mkdir -p "$CACHE_DIR"
    ssh_server "sudo cat /home/ubuntu/rustdesk/data/id_ed25519.pub; echo" > "$KEY_CACHE.tmp"
    mv "$KEY_CACHE.tmp" "$KEY_CACHE"
  fi
  cat "$KEY_CACHE"
}

cmd_autostop() {
  [ -n "${1:-}" ] || die "Usage: ./rd autostop <minutes|off>"
  ssh_server "sudo bash -s -- $(printf '%q' "$1")" < "$ROOT/server/install-autostop.sh"
}

# PowerShell single-quoted string literal.
ps_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }

# Double-clickable Windows file: a batch header that elevates itself, then
# runs the PowerShell after the ##PS# marker. Batch stops at "exit /b", so it
# never sees the PowerShell part.
write_windows_setup() {
  local key="$1" pw="$2" out="$3"
  {
    cat <<'EOF'
@echo off
rem RustDesk setup. Double-click to run. Contains a password: send privately.
set "RD_SELF=%~f0"
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath $env:RD_SELF"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = [IO.File]::ReadAllText($env:RD_SELF); iex $s.Substring($s.IndexOf('#' + '#PS#'))"
echo.
pause
exit /b
EOF
    echo '##PS#'
    echo "\$ServerIp = $(ps_quote "$SERVER_IP")"
    echo "\$ServerKey = $(ps_quote "$key")"
    echo "\$RdPassword = $(ps_quote "$pw")"
    cat "$ROOT/client/client-setup.ps1"
  } | awk '{ printf "%s\r\n", $0 }' > "$out"
}

write_unix_setup() {
  local key="$1" pw="$2" out="$3"
  {
    echo '#!/usr/bin/env bash'
    echo "# RustDesk setup, generated by ./rd client-setup on $(date +%Y-%m-%d). Contains a password: send privately."
    printf 'SERVER_IP=%q\n' "$SERVER_IP"
    printf 'SERVER_KEY=%q\n' "$key"
    printf 'RD_PASSWORD=%q\n' "$pw"
    cat "$ROOT/client/client-setup.sh"
  } > "$out"
  chmod 700 "$out"
}

cmd_client_setup() {
  local key pw pw2 dir="$ROOT/out"
  key="$(cmd_key)"
  read -rsp "Permanent password for the computer you support: " pw; echo
  read -rsp "Repeat: " pw2; echo
  [ "$pw" = "$pw2" ] || die "Passwords don't match."
  [ -n "$pw" ] || die "Password can't be empty."

  mkdir -p "$dir"
  write_windows_setup "$key" "$pw" "$dir/rustdesk-setup-windows.cmd"
  write_unix_setup "$key" "$pw" "$dir/rustdesk-setup-linux.sh"
  write_unix_setup "$key" "$pw" "$dir/rustdesk-setup-mac.command"

  cat <<EOF
Wrote to $dir/:
  rustdesk-setup-windows.cmd   Windows: double-click, then click Yes
  rustdesk-setup-linux.sh      Linux: right-click > Run as a Program
                               (or in a terminal: bash ~/Downloads/rustdesk-setup-linux.sh)
  rustdesk-setup-mac.command   Mac: double-click (first time: System Settings >
                               Privacy & Security > Open Anyway)

Send only the one they need, privately: each contains the password.
EOF
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  setup) cmd_setup ;;
  destroy) cmd_destroy ;;
  on) load_outputs; cmd_on ;;
  off) load_outputs; cmd_off ;;
  status) load_outputs; cmd_status ;;
  key) load_outputs; cmd_key ;;
  ssh) load_outputs; ssh_server "$@" ;;
  client-setup) load_outputs; cmd_client_setup ;;
  autostop) load_outputs; cmd_autostop "${1:-}" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
