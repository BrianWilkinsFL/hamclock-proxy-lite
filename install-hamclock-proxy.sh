#!/bin/bash
# =============================================================================
#  OHB Lite Proxy — Installer
#  Proxies clearskyinstitute.com, overrides /esats/esats.txt with local copy
#  Fetches TLE data and rebuilds esats.txt every 6 hours via systemd timer
# =============================================================================

set -e

# ── Config ────────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/hamclock-proxy"
BACKEND_DIR="/opt/hamclock-backend"
ESATS_DIR="${BACKEND_DIR}/htdocs/ham/HamClock/esats"
SCRIPTS_DIR="${BACKEND_DIR}/scripts"

SERVICE_NAME="hamclock-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

REFRESH_SERVICE_NAME="hamclock-esats-refresh"
REFRESH_SERVICE_FILE="/etc/systemd/system/${REFRESH_SERVICE_NAME}.service"
REFRESH_TIMER_FILE="/etc/systemd/system/${REFRESH_SERVICE_NAME}.timer"
REFRESH_SCRIPT="${INSTALL_DIR}/refresh_esats.sh"

PROXY_PORT=8083
PROXY_SCRIPT="${INSTALL_DIR}/proxy.py"

# The canonical esats.txt lives in the backend tree; the proxy symlinks to it
BACKEND_ESATS="${ESATS_DIR}/esats.txt"
BACKEND_ESATS1="${ESATS_DIR}/esats1.txt"
PROXY_ESATS_LINK="${INSTALL_DIR}/esats.txt"

UPSTREAM="http://clearskyinstitute.com"
REPO_URL="https://github.com/BrianWilkinsFL/open-hamclock-backend"
VERSION="1.0.0"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';     LRED='\033[1;31m'
GREEN='\033[0;32m';   LGREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m';    LCYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m';       DIM='\033[2m'
NC='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
warn()  { echo -e "  ${YELLOW}⚠${NC}  $*"; }
error() { echo -e "\n  ${LRED}✘  ERROR:${NC} $*\n" >&2; exit 1; }

# ── Spinner ───────────────────────────────────────────────────────────────────
_SPINNER_PID=""
_SPINNER_MSG=""

start_spinner() {
    _SPINNER_MSG="$1"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    (
        while true; do
            printf "\r  ${LCYAN}%s${NC}  %s   " "${frames[$i]}" "${_SPINNER_MSG}"
            i=$(( (i+1) % ${#frames[@]} ))
            sleep 0.08
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID"
}

stop_spinner() {
    local status="${1:-0}"
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi
    if [[ "$status" -eq 0 ]]; then
        printf "\r  ${LGREEN}✔${NC}  %-55s ${DIM}done${NC}\n" "${_SPINNER_MSG}"
    else
        printf "\r  ${LRED}✘${NC}  %-55s ${LRED}FAILED${NC}\n" "${_SPINNER_MSG}"
    fi
}

# ── Progress bar ──────────────────────────────────────────────────────────────
TOTAL_STEPS=18
CURRENT_STEP=0

advance() {
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    local label="${1:-Working}"
    local width=40
    local pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    local filled=$(( CURRENT_STEP * width / TOTAL_STEPS ))
    local empty=$(( width - filled ))

    local bar="${LGREEN}"
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    bar+="${DIM}"
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    bar+="${NC}"

    printf "  ${bar}  ${BOLD}%3d%%${NC}  ${DIM}%s${NC}\n" "$pct" "$label"
    sleep 0.12
}

# ── Section header ────────────────────────────────────────────────────────────
section() {
    echo
    echo -e "  ${BOLD}${LCYAN}┌─────────────────────────────────────────────────┐${NC}"
    printf  "  ${BOLD}${LCYAN}│${NC}  ${WHITE}%-47s${BOLD}${LCYAN}│${NC}\n" "$*"
    echo -e "  ${BOLD}${LCYAN}└─────────────────────────────────────────────────┘${NC}"
    echo
}

# ── ASCII Logo ────────────────────────────────────────────────────────────────
print_logo() {
    clear
    echo
    echo -e "${LCYAN}${BOLD}"
    echo '    ██████╗ ██╗  ██╗██████╗     ██╗     ██╗████████╗███████╗'
    echo '   ██╔═══██╗██║  ██║██╔══██╗    ██║     ██║╚══██╔══╝██╔════╝'
    echo '   ██║   ██║███████║██████╔╝    ██║     ██║   ██║   █████╗  '
    echo '   ██║   ██║██╔══██║██╔══██╗    ██║     ██║   ██║   ██╔══╝  '
    echo '   ╚██████╔╝██║  ██║██████╔╝    ███████╗██║   ██║   ███████╗'
    echo '    ╚═════╝ ╚═╝  ╚═╝╚═════╝     ╚══════╝╚═╝   ╚═╝   ╚══════╝'
    echo -e "${NC}"
    echo -e "  ${BOLD}${WHITE}           ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗${NC}"
    echo -e "  ${BOLD}${WHITE}           ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝${NC}"
    echo -e "  ${BOLD}${WHITE}           ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ${NC}"
    echo -e "  ${BOLD}${WHITE}           ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ${NC}"
    echo -e "  ${BOLD}${WHITE}           ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ${NC}"
    echo -e "  ${BOLD}${WHITE}           ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝  ${NC}"
    echo
    echo -e "  ${DIM}${CYAN}  ──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}       HamClock Reverse Proxy  •  clearskyinstitute.com${NC}"
    echo -e "  ${DIM}${CYAN}  ──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${DIM}    Version ${VERSION}                    Installer${NC}"
    echo
    sleep 0.5
}

# =============================================================================
#  BEGIN INSTALL
# =============================================================================

print_logo

echo -e "  ${BOLD}Configuration${NC}"
echo -e "  ${DIM}  Proxy install dir  :${NC} ${WHITE}${INSTALL_DIR}${NC}"
echo -e "  ${DIM}  Backend dir        :${NC} ${WHITE}${BACKEND_DIR}${NC}"
echo -e "  ${DIM}  esats output       :${NC} ${WHITE}${BACKEND_ESATS}${NC}"
echo -e "  ${DIM}  Proxy symlink      :${NC} ${WHITE}${PROXY_ESATS_LINK}${NC}"
echo -e "  ${DIM}  Listen port        :${NC} ${WHITE}${PROXY_PORT}${NC}"
echo -e "  ${DIM}  Upstream           :${NC} ${WHITE}${UPSTREAM}${NC}"
echo -e "  ${DIM}  Refresh schedule   :${NC} ${WHITE}Every 6 hours${NC}"
echo

# ── Preflight ─────────────────────────────────────────────────────────────────
section "Preflight Checks"

start_spinner "Checking root privileges"
sleep 0.3
[[ $EUID -ne 0 ]] && { stop_spinner 1; error "Please run as root: sudo $0"; }
stop_spinner 0
advance "Root check passed"

start_spinner "Locating python3"
sleep 0.3
python3 --version &>/dev/null || { stop_spinner 1; error "python3 not found — sudo apt install python3"; }
PYTHON_VER=$(python3 --version 2>&1)
stop_spinner 0
advance "${PYTHON_VER} found"

start_spinner "Locating perl"
sleep 0.3
perl --version &>/dev/null || { stop_spinner 1; error "perl not found — sudo apt install perl"; }
stop_spinner 0
advance "perl found"

start_spinner "Verifying systemd"
sleep 0.3
systemctl --version &>/dev/null || { stop_spinner 1; error "systemd not found."; }
stop_spinner 0
advance "systemd present"

start_spinner "Checking port ${PROXY_PORT} availability"
sleep 0.3
if ss -tlnp 2>/dev/null | grep -q ":${PROXY_PORT} "; then
    stop_spinner 1
    warn "Port ${PROXY_PORT} already in use — edit PROXY_PORT at the top of this script."
else
    stop_spinner 0
fi
advance "Port ${PROXY_PORT} checked"

# ── Prepare directories ────────────────────────────────────────────────────────
section "Preparing Directories"

start_spinner "Stopping existing services (if running)"
for svc in "${SERVICE_NAME}" "${REFRESH_SERVICE_NAME}"; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        systemctl stop "${svc}" 2>/dev/null || true
    fi
done
sleep 0.4
stop_spinner 0

start_spinner "Creating proxy directory  ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
sleep 0.2
stop_spinner 0

start_spinner "Creating backend scripts directory  ${SCRIPTS_DIR}"
mkdir -p "${SCRIPTS_DIR}"
sleep 0.2
stop_spinner 0

start_spinner "Creating esats output directory  ${ESATS_DIR}"
mkdir -p "${ESATS_DIR}"
sleep 0.2
stop_spinner 0
advance "Directories ready"

# ── Clone / update backend scripts ────────────────────────────────────────────
section "Fetching Backend Scripts"

start_spinner "Checking for git"
HAS_GIT=0
git --version &>/dev/null && HAS_GIT=1
sleep 0.2
stop_spinner 0

if [[ $HAS_GIT -eq 1 ]]; then
    start_spinner "Sparse-cloning 3 files from open-hamclock-backend"
    TMP_CLONE=$(mktemp -d)
    (
        cd "${TMP_CLONE}"
        git clone --quiet --no-checkout --depth=1 --filter=blob:none \
            "${REPO_URL}" repo
        cd repo
        git sparse-checkout init --cone
        git sparse-checkout set scripts ham/HamClock/esats
        git checkout --quiet main
    )

    # Copy the two scripts
    cp "${TMP_CLONE}/repo/scripts/fetch_tle.sh"   "${SCRIPTS_DIR}/fetch_tle.sh"
    cp "${TMP_CLONE}/repo/scripts/build_esats.pl" "${SCRIPTS_DIR}/build_esats.pl"

    # Copy esats1.txt — only if not already present (preserve any live version)
    if [[ ! -f "${BACKEND_ESATS1}" ]]; then
        cp "${TMP_CLONE}/repo/ham/HamClock/esats/esats1.txt" "${BACKEND_ESATS1}"
    fi

    rm -rf "${TMP_CLONE}"
    stop_spinner 0
else
    stop_spinner 0
    warn "git not found — skipping auto-clone. Manually copy into ${SCRIPTS_DIR}/:"
    warn "  fetch_tle.sh, build_esats.pl"
    warn "And copy ham/HamClock/esats/esats1.txt from the repo to ${BACKEND_ESATS1}"
fi
advance "Backend scripts ready"

# Make scripts executable
chmod +x "${SCRIPTS_DIR}/fetch_tle.sh"
chmod +x "${SCRIPTS_DIR}/build_esats.pl"

start_spinner "Verifying esats1.txt baseline"
sleep 0.2
[[ -f "${BACKEND_ESATS1}" ]] && stop_spinner 0 || { stop_spinner 1; warn "esats1.txt missing — refresh may fail on first run."; }
advance "esats1.txt ready"

# ── Create placeholder esats.txt if nothing there yet ─────────────────────────
if [[ ! -f "${BACKEND_ESATS}" ]]; then
    cp "${BACKEND_ESATS1}" "${BACKEND_ESATS}" 2>/dev/null || touch "${BACKEND_ESATS}"
fi

# ── Symlink backend esats.txt → proxy dir ─────────────────────────────────────
start_spinner "Symlinking  ${BACKEND_ESATS}  →  ${PROXY_ESATS_LINK}"
# Remove any old plain file or stale symlink at the proxy location
rm -f "${PROXY_ESATS_LINK}"
ln -s "${BACKEND_ESATS}" "${PROXY_ESATS_LINK}"
sleep 0.2
stop_spinner 0
advance "Symlink created"

# ── Write the refresh wrapper script ─────────────────────────────────────────
section "Installing Refresh Scripts"

start_spinner "Writing refresh_esats.sh"
cat > "${REFRESH_SCRIPT}" << REFRESHEOF
#!/bin/bash
# =============================================================================
#  OHB Lite Proxy — esats refresh script
#  Runs fetch_tle.sh then build_esats.pl every 6 hours via systemd timer
# =============================================================================

set -euo pipefail
umask 022   # ensure all written files are world-readable (proxy runs as nobody)

SCRIPTS_DIR="${SCRIPTS_DIR}"
ESATS_DIR="${ESATS_DIR}"
LOG_TAG="ohb-esats-refresh"

log()  { echo "\$(date '+%Y-%m-%d %H:%M:%S') INFO  \$*"; }
err()  { echo "\$(date '+%Y-%m-%d %H:%M:%S') ERROR \$*" >&2; }

log "=== OHB esats refresh starting ==="

# ── Step 1: Fetch fresh TLE data ─────────────────────────────────────────────
log "Running fetch_tle.sh ..."
if bash "\${SCRIPTS_DIR}/fetch_tle.sh"; then
    log "fetch_tle.sh completed successfully."
else
    err "fetch_tle.sh failed — aborting refresh."
    exit 1
fi

# ── Step 2: Build esats.txt from TLE data ────────────────────────────────────
log "Running build_esats.pl ..."
if ESATS_OUT="${ESATS_DIR}/esats.txt" \
   ESATS_ORIGINAL="${ESATS_DIR}/esats1.txt" \
   perl "\${SCRIPTS_DIR}/build_esats.pl"; then
    log "build_esats.pl completed successfully."
else
    err "build_esats.pl failed — previous esats.txt retained."
    exit 1
fi

log "=== esats refresh complete — $(wc -l < "${ESATS_DIR}/esats.txt") lines in esats.txt ==="
REFRESHEOF

chmod +x "${REFRESH_SCRIPT}"
stop_spinner 0
advance "refresh_esats.sh written"

# ── Write proxy.py ─────────────────────────────────────────────────────────────
section "Installing Proxy Engine"

start_spinner "Writing proxy.py"
cat > "${PROXY_SCRIPT}" << 'PYEOF'
#!/usr/bin/env python3
"""
OHB Lite Proxy
--------------
Transparently proxies requests to clearskyinstitute.com.
Paths listed in LOCAL_OVERRIDES are served from local files instead.
The esats.txt entry points at a symlink that is refreshed every 6 hours
by the hamclock-esats-refresh systemd timer.
"""

import http.server
import urllib.request
import urllib.error
import os
import sys
import logging

# ── Settings (edited by installer) ───────────────────────────────────────────
UPSTREAM        = "@@UPSTREAM@@"
LISTEN_HOST     = "0.0.0.0"
LISTEN_PORT     = @@PORT@@
LOCAL_OVERRIDES = {
    "/ham/HamClock/esats/esats.txt": "@@PROXY_ESATS_LINK@@",
}
# ─────────────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("ohb-lite-proxy")

HOPBYHOP = {"transfer-encoding", "connection", "keep-alive",
            "proxy-authenticate", "proxy-authorization", "te", "trailers", "upgrade"}


class ProxyHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        self._handle()

    def do_HEAD(self):
        self._handle(head_only=True)

    def _handle(self, head_only=False):
        path = self.path

        # ── Local override? ───────────────────────────────────────────────────
        if path in LOCAL_OVERRIDES:
            local_path = LOCAL_OVERRIDES[path]
            resolved = os.path.realpath(local_path)
            if os.path.isfile(resolved):
                log.info("OVERRIDE  %s  ->  %s  (resolved: %s)", path, local_path, resolved)
                try:
                    with open(resolved, "rb") as fh:
                        data = fh.read()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain; charset=utf-8")
                    self.send_header("Content-Length", str(len(data)))
                    self.send_header("X-Proxy-Source", "local-override")
                    self.end_headers()
                    if not head_only:
                        self.wfile.write(data)
                    return
                except OSError as exc:
                    log.error("Cannot read local file %s: %s", resolved, exc)
            else:
                log.warning("Override target missing or broken symlink (%s -> %s), "
                            "falling through to upstream", local_path, resolved)

        # ── Proxy to upstream ─────────────────────────────────────────────────
        url = UPSTREAM + path
        log.info("PROXY     %s  ->  %s", path, url)

        try:
            headers = {
                "User-Agent": self.headers.get("User-Agent", "OHBLiteProxy/1.0"),
                "Accept":     self.headers.get("Accept", "*/*"),
            }
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read()
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in HOPBYHOP:
                        self.send_header(k, v)
                self.send_header("X-Proxy-Source", "upstream")
                self.end_headers()
                if not head_only:
                    self.wfile.write(body)

        except urllib.error.HTTPError as exc:
            log.warning("Upstream HTTP %s for %s", exc.code, url)
            self.send_response(exc.code)
            self.end_headers()

        except urllib.error.URLError as exc:
            log.error("Upstream unreachable for %s: %s", url, exc.reason)
            self.send_response(502)
            self.end_headers()

        except Exception as exc:
            log.error("Unexpected error for %s: %s", url, exc)
            self.send_response(500)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else LISTEN_PORT
    server = http.server.ThreadingHTTPServer((LISTEN_HOST, port), ProxyHandler)
    log.info("OHB Lite Proxy started  --  listening on %s:%d", LISTEN_HOST, port)
    log.info("Upstream: %s", UPSTREAM)
    log.info("Local overrides: %s", LOCAL_OVERRIDES)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Shutting down.")
        server.server_close()
PYEOF

sed -i "s|@@UPSTREAM@@|${UPSTREAM}|g"           "${PROXY_SCRIPT}"
sed -i "s|@@PORT@@|${PROXY_PORT}|g"             "${PROXY_SCRIPT}"
sed -i "s|@@PROXY_ESATS_LINK@@|${PROXY_ESATS_LINK}|g" "${PROXY_SCRIPT}"
chmod +x "${PROXY_SCRIPT}"
stop_spinner 0
advance "proxy.py written & configured"

# ── systemd: proxy service ─────────────────────────────────────────────────────
section "Registering System Services"

start_spinner "Writing proxy systemd unit"
cat > "${SERVICE_FILE}" << SVCEOF
[Unit]
Description=OHB Lite Proxy (clearskyinstitute.com)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${PROXY_SCRIPT} ${PROXY_PORT}
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
User=nobody
Group=nogroup
ReadOnlyPaths=${INSTALL_DIR} ${ESATS_DIR}
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF
sleep 0.2
stop_spinner 0
advance "Proxy service unit written"

# ── systemd: refresh oneshot service ─────────────────────────────────────────
start_spinner "Writing esats refresh service unit"
cat > "${REFRESH_SERVICE_FILE}" << RSVCEOF
[Unit]
Description=OHB Lite Proxy — Refresh esats.txt from TLE data
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${REFRESH_SCRIPT}
WorkingDirectory=${BACKEND_DIR}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${REFRESH_SERVICE_NAME}
# Run as root so scripts can write to backend dirs
# (tighten this if your scripts run as a dedicated user)
User=root

[Install]
WantedBy=multi-user.target
RSVCEOF
sleep 0.2
stop_spinner 0

# ── systemd: 6-hour timer ─────────────────────────────────────────────────────
start_spinner "Writing 6-hour refresh timer"
cat > "${REFRESH_TIMER_FILE}" << TIMEREOF
[Unit]
Description=OHB Lite Proxy — Refresh esats every 6 hours
Requires=${REFRESH_SERVICE_NAME}.service

[Timer]
# Run 2 minutes after boot, then every 6 hours
OnBootSec=2min
OnUnitActiveSec=6h
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF
sleep 0.2
stop_spinner 0
advance "Timer unit written"

# ── Permissions ───────────────────────────────────────────────────────────────
start_spinner "Setting file permissions"
chown -R nobody:nogroup "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"
chmod 755 "${PROXY_SCRIPT}"
# Backend dirs need to be writable by root (refresh runs as root)
chown -R root:root "${BACKEND_DIR}"
chmod 755 "${ESATS_DIR}"
chmod 644 "${BACKEND_ESATS}" 2>/dev/null || true
chmod 644 "${BACKEND_ESATS1}" 2>/dev/null || true
# Symlink itself inherits permissions from target; readable by nobody
sleep 0.3
stop_spinner 0
advance "Permissions set"

# ── Enable and start everything ────────────────────────────────────────────────
start_spinner "Reloading systemd daemon"
systemctl daemon-reload
sleep 0.4
stop_spinner 0

start_spinner "Enabling proxy service"
systemctl enable "${SERVICE_NAME}" &>/dev/null
sleep 0.2
stop_spinner 0

start_spinner "Enabling esats refresh timer"
systemctl enable "${REFRESH_SERVICE_NAME}.timer" &>/dev/null
sleep 0.2
stop_spinner 0

start_spinner "Starting proxy service"
systemctl restart "${SERVICE_NAME}"
sleep 2
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    stop_spinner 0
else
    stop_spinner 1
    error "Proxy service failed to start.\nCheck: journalctl -u ${SERVICE_NAME} -n 50"
fi
advance "Proxy service running"

start_spinner "Starting esats refresh timer"
systemctl start "${REFRESH_SERVICE_NAME}.timer"
sleep 0.5
stop_spinner 0
advance "Refresh timer running"

start_spinner "Running initial esats refresh now"
# Run the refresh service immediately so esats.txt is populated right away
if systemctl start "${REFRESH_SERVICE_NAME}.service" 2>/dev/null; then
    # Wait up to 30s for the oneshot to complete
    timeout 30 systemctl is-active --quiet "${REFRESH_SERVICE_NAME}.service" 2>/dev/null || true
    sleep 2
    stop_spinner 0
else
    stop_spinner 1
    warn "Initial refresh did not complete — will retry at next timer tick (within 6h)."
    warn "Run manually: sudo systemctl start ${REFRESH_SERVICE_NAME}.service"
fi
advance "Initial esats populated"

# ── Final 100% bar ────────────────────────────────────────────────────────────
echo
width=40
bar="${LGREEN}"
for (( i=0; i<width; i++ )); do bar+="█"; done
bar+="${NC}"
printf "  ${bar}  ${BOLD}100%%${NC}  ${LGREEN}Installation complete!${NC}\n"
sleep 0.2

# ── Detect local IP ───────────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

# ── Next timer tick ───────────────────────────────────────────────────────────
NEXT_TIMER=$(systemctl list-timers "${REFRESH_SERVICE_NAME}.timer" --no-pager 2>/dev/null \
    | awk 'NR==2 {print $1, $2}' || echo "unknown")

# ── Done banner ───────────────────────────────────────────────────────────────
echo
echo -e "  ${LGREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${LGREEN}${BOLD}║        ✔  OHB Lite Proxy is live!                   ║${NC}"
echo -e "  ${LGREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo
echo -e "  ${BOLD}Connect HamClock with:${NC}"
if [[ -n "${LOCAL_IP}" ]]; then
    echo -e "    ${WHITE}hamclock ${LCYAN}-b ${LOCAL_IP}:${PROXY_PORT}${NC}"
else
    echo -e "    ${WHITE}hamclock ${LCYAN}-b <raspberry-pi-ip>:${PROXY_PORT}${NC}"
fi
echo
echo -e "  ${BOLD}esats.txt data flow:${NC}"
echo -e "    ${DIM}fetch_tle.sh → build_esats.pl → ${BACKEND_ESATS}${NC}"
echo -e "    ${DIM}               symlink ↑${NC}"
echo -e "    ${DIM}             ${PROXY_ESATS_LINK}${NC}"
echo -e "    ${DIM}               served ↑ by proxy on /esats/esats.txt${NC}"
echo
echo -e "  ${BOLD}Refresh schedule:${NC}  every 6 hours  ${DIM}(next: ${NEXT_TIMER})${NC}"
echo
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "    ${DIM}Proxy status   :${NC}  sudo systemctl status ${SERVICE_NAME}"
echo -e "    ${DIM}Proxy logs     :${NC}  sudo journalctl -u ${SERVICE_NAME} -f"
echo -e "    ${DIM}Refresh logs   :${NC}  sudo journalctl -u ${REFRESH_SERVICE_NAME} -f"
echo -e "    ${DIM}Force refresh  :${NC}  sudo systemctl start ${REFRESH_SERVICE_NAME}.service"
echo -e "    ${DIM}Timer status   :${NC}  sudo systemctl list-timers ${REFRESH_SERVICE_NAME}.timer"
echo -e "    ${DIM}Restart proxy  :${NC}  sudo systemctl restart ${SERVICE_NAME}"
echo
echo -e "  ${BOLD}Uninstall:${NC}"
echo -e "    ${DIM}sudo systemctl disable --now ${SERVICE_NAME} ${REFRESH_SERVICE_NAME}.timer${NC}"
echo -e "    ${DIM}sudo rm -f ${SERVICE_FILE} ${REFRESH_SERVICE_FILE} ${REFRESH_TIMER_FILE}${NC}"
echo -e "    ${DIM}sudo rm -rf ${INSTALL_DIR}${NC}"
echo
