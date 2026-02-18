#!/bin/bash
# =============================================================================
#  OHB Lite Proxy — Installer
#  Proxies clearskyinstitute.com, overrides /esats/esats.txt with local copy
# =============================================================================

set -e

# ── Config ────────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/hamclock-proxy"
SERVICE_NAME="hamclock-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PROXY_PORT=8083
PROXY_SCRIPT="${INSTALL_DIR}/proxy.py"
ESATS_FILE="${INSTALL_DIR}/esats.txt"
UPSTREAM="http://clearskyinstitute.com"
VERSION="1.0.0"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';     LRED='\033[1;31m'
GREEN='\033[0;32m';   LGREEN='\033[1;32m'
YELLOW='\033[1;33m';
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
# Usage: progress_bar <current> <total> <label>
TOTAL_STEPS=9
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
echo -e "  ${DIM}  Install dir  :${NC} ${WHITE}${INSTALL_DIR}${NC}"
echo -e "  ${DIM}  Listen port  :${NC} ${WHITE}${PROXY_PORT}${NC}"
echo -e "  ${DIM}  Upstream     :${NC} ${WHITE}${UPSTREAM}${NC}"
echo

# ── Preflight ─────────────────────────────────────────────────────────────────
section "Preflight Checks"

start_spinner "Checking root privileges"
sleep 0.3
if [[ $EUID -ne 0 ]]; then stop_spinner 1; error "Please run as root: sudo $0"; fi
stop_spinner 0
advance "Root check passed"

start_spinner "Locating python3"
sleep 0.3
if ! python3 --version &>/dev/null; then stop_spinner 1; error "python3 not found — install with: sudo apt install python3"; fi
PYTHON_VER=$(python3 --version 2>&1)
stop_spinner 0
advance "${PYTHON_VER} found"

start_spinner "Verifying systemd"
sleep 0.3
if ! systemctl --version &>/dev/null; then stop_spinner 1; error "systemd not found on this system."; fi
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

# ── Prepare environment ───────────────────────────────────────────────────────
section "Preparing Environment"

start_spinner "Stopping existing service (if running)"
if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
fi
sleep 0.4
stop_spinner 0

start_spinner "Creating install directory  ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
sleep 0.3
stop_spinner 0
advance "Environment ready"

# ── Write proxy.py ────────────────────────────────────────────────────────────
section "Installing Proxy Engine"

start_spinner "Writing proxy.py"
cat > "${PROXY_SCRIPT}" << 'PYEOF'
#!/usr/bin/env python3
"""
OHB Lite Proxy
--------------
Transparently proxies requests to clearskyinstitute.com.
Paths listed in LOCAL_OVERRIDES are served from local files instead.
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
    "/esats/esats.txt": "@@ESATS_FILE@@",
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
            if os.path.isfile(local_path):
                log.info("OVERRIDE  %s  ->  %s", path, local_path)
                try:
                    with open(local_path, "rb") as fh:
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
                    log.error("Cannot read local file %s: %s", local_path, exc)
            else:
                log.warning("Override file missing (%s), falling through to upstream", local_path)

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
        pass  # We use our own structured logging


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

sed -i "s|@@UPSTREAM@@|${UPSTREAM}|g"     "${PROXY_SCRIPT}"
sed -i "s|@@PORT@@|${PROXY_PORT}|g"       "${PROXY_SCRIPT}"
sed -i "s|@@ESATS_FILE@@|${ESATS_FILE}|g" "${PROXY_SCRIPT}"
chmod +x "${PROXY_SCRIPT}"
stop_spinner 0
advance "proxy.py written & configured"

# ── esats.txt ─────────────────────────────────────────────────────────────────
start_spinner "Setting up local esats.txt override"
if [[ ! -f "${ESATS_FILE}" ]]; then
    cat > "${ESATS_FILE}" << 'ESEOF'
# OHB Lite Proxy — local esats.txt override
# Replace this file with your custom satellite element data.
# Format matches the clearskyinstitute.com /esats/esats.txt file.
ESEOF
    sleep 0.3
    stop_spinner 0
    warn "Placeholder created — edit ${ESATS_FILE} with real satellite data."
else
    sleep 0.3
    stop_spinner 0
fi
advance "esats.txt override ready"

# ── systemd service ───────────────────────────────────────────────────────────
section "Registering System Service"

start_spinner "Writing systemd unit file"
cat > "${SERVICE_FILE}" << SVCEOF
[Unit]
Description=OHB Lite Proxy (clearskyinstitute.com)
Documentation=https://www.clearskyinstitute.com/ham/HamClock/
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
ReadOnlyPaths=${INSTALL_DIR}
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF
sleep 0.3
stop_spinner 0

start_spinner "Setting file permissions"
chown -R nobody:nogroup "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"
chmod 644 "${ESATS_FILE}"
chmod 755 "${PROXY_SCRIPT}"
sleep 0.3
stop_spinner 0

start_spinner "Reloading systemd daemon"
systemctl daemon-reload
sleep 0.4
stop_spinner 0

start_spinner "Enabling service at boot"
systemctl enable "${SERVICE_NAME}" &>/dev/null
sleep 0.3
stop_spinner 0

start_spinner "Starting OHB Lite Proxy"
systemctl restart "${SERVICE_NAME}"
sleep 2
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    stop_spinner 0
else
    stop_spinner 1
    error "Service failed to start.\nCheck logs with: journalctl -u ${SERVICE_NAME} -n 50"
fi
advance "Service running"

# ── Final 100% progress flush ─────────────────────────────────────────────────
echo
# Draw the completed bar one final time at 100%
width=40
bar="${LGREEN}"
for (( i=0; i<width; i++ )); do bar+="█"; done
bar+="${NC}"
printf "  ${bar}  ${BOLD}100%%${NC}  ${LGREEN}Installation complete!${NC}\n"
sleep 0.2

# ── Detect local IP ───────────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

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
echo -e "  ${BOLD}Local esats.txt override:${NC}"
echo -e "    ${DIM}${ESATS_FILE}${NC}"
echo
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "    ${DIM}Status   :${NC}  sudo systemctl status ${SERVICE_NAME}"
echo -e "    ${DIM}Logs     :${NC}  sudo journalctl -u ${SERVICE_NAME} -f"
echo -e "    ${DIM}Restart  :${NC}  sudo systemctl restart ${SERVICE_NAME}"
echo -e "    ${DIM}Stop     :${NC}  sudo systemctl stop ${SERVICE_NAME}"
echo -e "    ${DIM}Uninstall:${NC}  sudo systemctl disable --now ${SERVICE_NAME}"
echo -e "             ${DIM}sudo rm -f ${SERVICE_FILE}${NC}"
echo -e "             ${DIM}sudo rm -rf ${INSTALL_DIR}${NC}"
echo
