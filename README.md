# 📡 OHB Lite Proxy

A lightweight HamClock reverse proxy for Raspberry Pi. Transparently forwards requests to `clearskyinstitute.com` while allowing local overrides for specific files.

---

## ✨ Features

- 🔀 Proxies all HamClock traffic to `clearskyinstitute.com`
- 📄 Serves `/esats/esats.txt` from a **local file** instead of upstream
- 🔒 Runs as `nobody` with systemd hardening
- 🐍 Zero dependencies — pure Python 3 stdlib
- 🚀 One-command install with animated progress

---

## ⚡ Quick Install

```bash
chmod +x install-hamclock-proxy.sh
sudo ./install-hamclock-proxy.sh
```

---

## 🔌 Connecting HamClock

**Same machine:**
```
hamclock -b 127.0.0.1:8083
```

**Remote Pi on your network:**
```
hamclock -b <pi-ip-address>:8083
```

---

## 📁 File Locations

| Path | Purpose |
|------|---------|
| `/opt/hamclock-proxy/proxy.py` | Proxy server |
| `/opt/hamclock-proxy/esats.txt` | Your local esats override |
| `/etc/systemd/system/hamclock-proxy.service` | systemd unit |

---

## 🛰️ Customising esats.txt

Edit the local override file to serve your own satellite elements:

```bash
sudo nano /opt/hamclock-proxy/esats.txt
sudo systemctl restart hamclock-proxy
```

Format matches the upstream `clearskyinstitute.com/esats/esats.txt` file.

---

## 🛠️ Service Management

```bash
# Status
sudo systemctl status hamclock-proxy

# Live logs
sudo journalctl -u hamclock-proxy -f

# Restart / Stop
sudo systemctl restart hamclock-proxy
sudo systemctl stop hamclock-proxy
```

---

## 🗑️ Uninstall

```bash
sudo systemctl disable --now hamclock-proxy
sudo rm -f /etc/systemd/system/hamclock-proxy.service
sudo rm -rf /opt/hamclock-proxy
```

---

## 📋 Requirements

- Raspberry Pi OS (or any Linux with systemd)
- Python 3 (`sudo apt install python3`)
- Root access for install
