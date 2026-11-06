"""
Roku Febbox Key Injector + Deployer
- Replace the Febbox token in components/Config.brs before deployment.
- Auto-discover Roku device on local network.
- Build the channel zip and deploy to the Roku dev server.

Usage: python roku_inject_deploy.py
Requires: Python 3.8+, tkinter (built-in), requests
"""
import json
import os
import re
import socket
import subprocess
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

import requests
from requests.auth import HTTPDigestAuth

import sys

if getattr(sys, "frozen", False):
    ROOT = os.path.dirname(sys.executable)
else:
    ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_BRs = os.path.join(ROOT, "components", "Config.brs")
OUT_ZIP = os.path.join(ROOT, "out", "roku.zip")

DEFAULT_USER = "rokudev"
DEFAULT_PASS = "1234"


def read_febbox_token():
    try:
        with open(CONFIG_BRs, "r", encoding="utf-8") as f:
            txt = f.read()
        m = re.search(r'febboxToken:\s*"([^"]*)"', txt)
        return m.group(1) if m else ""
    except Exception:
        return ""


def read_tmdb_key():
    try:
        with open(CONFIG_BRs, "r", encoding="utf-8") as f:
            txt = f.read()
        m = re.search(r'tmdbKey:\s*"([^"]*)"', txt)
        if m:
            return m.group(1)
        m = re.search(r'tmdbDefaultKey:\s*"([^"]*)"', txt)
        return m.group(1) if m else ""
    except Exception:
        return ""


def replace_febbox_token(new_token):
    new_token = (new_token or "").strip()
    if not new_token:
        raise ValueError("Febbox token must not be empty")
    with open(CONFIG_BRs, "r", encoding="utf-8") as f:
        txt = f.read()

    # 1. Replace the active token (first occurrence only).
    new_txt, n_active = re.subn(
        r'febboxToken:\s*"[^"]*"',
        lambda _m: 'febboxToken: "' + new_token + '"',
        txt,
        count=1,
    )
    if n_active == 0:
        raise RuntimeError("febboxToken field not found in Config.brs")

    # 2. Rebuild the rotation list so the new token is first and de-duplicated,
    #    keeping any other saved tokens after it.
    def rebuild_list(m):
        inner = m.group(1)
        entries = re.findall(r'"([^"]*)"', inner)
        seen = {new_token}
        ordered = [new_token]
        for e in entries:
            if e and e not in seen:
                ordered.append(e)
                seen.add(e)
        joined = ",\n            ".join('"' + e + '"' for e in ordered)
        return "febboxTokens: [\n            " + joined + "\n        ]"

    new_txt, n_list = re.subn(
        r"febboxTokens:\s*\[(.*?)\]",
        rebuild_list,
        new_txt,
        count=1,
        flags=re.S,
    )
    # If no list existed, insert one right after the active token line.
    if n_list == 0:
        new_txt, n_ins = re.subn(
            r'(febboxToken:\s*"[^"]*"\s*,\n)',
            r'\1        febboxTokens: [\n            "' + new_token + '"\n        ],\n',
            new_txt,
            count=1,
        )
        n_list = n_ins

    # Atomic write so a crash cannot leave a half-written Config.brs.
    tmp = CONFIG_BRs + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(new_txt)
    os.replace(tmp, CONFIG_BRs)
    return n_active + n_list


def replace_tmdb_key(new_key):
    new_key = (new_key or "").strip()
    if not new_key:
        raise ValueError("TMDB key must not be empty")
    with open(CONFIG_BRs, "r", encoding="utf-8") as f:
        txt = f.read()

    new_txt, n = re.subn(
        r'tmdbKey:\s*"[^"]*"',
        lambda _m: 'tmdbKey: "' + new_key + '"',
        txt,
        count=1,
    )
    if n == 0:
        new_txt, n = re.subn(
            r'tmdbDefaultKey:\s*"[^"]*"',
            lambda _m: 'tmdbDefaultKey: "' + new_key + '"',
            new_txt,
            count=1,
        )
    if n == 0:
        raise RuntimeError("tmdbKey field not found in Config.brs")

    tmp = CONFIG_BRs + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(new_txt)
    os.replace(tmp, CONFIG_BRs)
    return n


def discover_roku(progress_cb=None):
    """Scan local subnets concurrently for a Roku device (port 8060 ECP)."""
    from concurrent.futures import ThreadPoolExecutor, as_completed

    subnets = set()
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None):
            ip = info[4][0]
            if "." in ip and not ip.startswith("127."):
                parts = ip.split(".")
                subnets.add(".".join(parts[:3]))
    except Exception:
        pass
    subnets.update(["192.168.0", "192.168.1", "10.0.0", "172.16.0"])

    candidates = [f"{s}.{i}" for s in subnets for i in range(1, 255)]
    found = []
    total = len(candidates)
    done = 0

    def check(ip):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(0.2)
            if s.connect_ex((ip, 8060)) == 0:
                s.close()
                try:
                    r = requests.get(f"http://{ip}:8060/query/device-info", timeout=2)
                    if "roku" in r.text.lower():
                        name = "Roku"
                        m = re.search(r"<friendly-device-name>([^<]*)</friendly-device-name>", r.text)
                        if m:
                            name = m.group(1)
                        return (ip, name)
                except Exception:
                    pass
            else:
                s.close()
        except Exception:
            pass
        return None

    with ThreadPoolExecutor(max_workers=128) as ex:
        futures = {ex.submit(check, ip): ip for ip in candidates}
        for fut in as_completed(futures):
            res = fut.result()
            done += 1
            if res:
                found.append(res)
                if progress_cb:
                    progress_cb("found", res[0], len(found), done, total)
            if progress_cb and done % 500 == 0:
                progress_cb("scan", None, len(found), done, total)
    if progress_cb:
        progress_cb("done", None, len(found), total, total)
    return found


def _node_command(script_args):
    """Resolve a runnable node invocation.

    On Windows, ``node`` is frequently installed as a ``.cmd``/``.bat`` shim
    (nvm-windows, the official installer's PATH entry, ...). ``subprocess.run``
    with a list and ``shell=False`` calls ``CreateProcess`` directly on that
    shim, which fails with ``[WinError 193] %1 is not a valid Win32
    application``. Detect that case and route through ``cmd.exe`` so the shim is
    resolved normally. On other platforms (or when a real ``node`` binary is
    found) the list form is used as before.
    """
    import shutil
    import sys

    node = shutil.which("node")
    if node and node.lower().endswith((".cmd", ".bat")):
        return ["cmd", "/c", "node"] + list(script_args), False
    if node:
        return [node] + list(script_args), False
    # Fallback: let the shell resolve it.
    if sys.platform == "win32":
        return "node " + " ".join(script_args), True
    return ["node"] + list(script_args), False


def run_compile(log_cb):
    log_cb("Compiling (node tools/compile.js)...")
    cmd, shell = _node_command(["tools/compile.js"])
    proc = subprocess.run(
        cmd,
        cwd=ROOT,
        capture_output=True,
        text=True,
        shell=shell,
    )
    if proc.stdout:
        log_cb(proc.stdout.rstrip())
    if proc.stderr:
        log_cb(proc.stderr.rstrip())
    m = re.search(r"errors=(\d+)", proc.stdout or "")
    if m:
        if int(m.group(1)) > 0:
            raise RuntimeError("Compile failed: %d error(s)" % int(m.group(1)))
    elif proc.returncode != 0:
        raise RuntimeError("Compile failed (exit %d)" % proc.returncode)


def build_package(log_cb):
    run_compile(log_cb)
    log_cb("Building package (node tools/package.js)...")
    try:
        if os.path.exists(OUT_ZIP):
            os.remove(OUT_ZIP)
    except OSError:
        pass
    cmd, shell = _node_command(["tools/package.js"])
    proc = subprocess.run(
        cmd,
        cwd=ROOT,
        capture_output=True,
        text=True,
        shell=shell,
    )
    if proc.stdout:
        log_cb(proc.stdout.rstrip())
    if proc.stderr:
        log_cb(proc.stderr.rstrip())
    if proc.returncode != 0:
        raise RuntimeError("Build failed (exit %d)" % proc.returncode)
    if not os.path.exists(OUT_ZIP):
        raise RuntimeError("roku.zip not produced")
    log_cb(f"Built {OUT_ZIP}")


def _request(session, method, url, log_cb=None, attempts=3, **kwargs):
    # Roku's installer is known to drop connections mid digest handshake.
    # A connection that is aborted before any response is safe to retry.
    last = None
    for i in range(1, attempts + 1):
        try:
            return session.request(method, url, **kwargs)
        except requests.exceptions.ConnectionError as e:
            last = e
            if log_cb:
                log_cb(f"  attempt {i}/{attempts} aborted, retrying...")
            time.sleep(1.0 * i)
    raise last


def deploy(ip, user, password, log_cb):
    auth = HTTPDigestAuth(user, password)
    base = f"http://{ip}"
    session = requests.Session()
    # Delete existing
    log_cb("Deleting existing dev channel...")
    try:
        rd = _request(session, "POST", f"{base}/plugin_install", log_cb,
                      auth=auth, data={"mysubmit": "Delete"}, timeout=15)
        log_cb(f"  delete HTTP {rd.status_code}")
    except Exception as e:
        log_cb(f"  Delete warning: {e}")
    time.sleep(0.5)
    # Install
    log_cb("Installing zip...")
    if not os.path.exists(OUT_ZIP):
        raise RuntimeError("roku.zip not found; build first")
    with open(OUT_ZIP, "rb") as f:
        files = {"archive": ("roku.zip", f, "application/zip")}
        data = {"mysubmit": "Install"}
        r = _request(session, "POST", f"{base}/plugin_install", log_cb,
                     auth=auth, data=data, files=files, timeout=120)
    log_cb(f"  install HTTP {r.status_code}")
    m = re.search(r"params\.messages\s*=\s*(?P<json>\[.*?\])", r.text, re.S)
    msgs = []
    if m:
        try:
            msgs = json.loads(m.group("json").replace("&quot;", '"').replace("&amp;", "&"))
        except Exception:
            log_cb(r.text[:500])
    else:
        log_cb(r.text[:500])

    ok = True
    for msg in msgs:
        log_cb(f"  [{msg.get('type', '?')}] {msg.get('text', '')}")
        t = str(msg.get("type", "")).lower()
        txt = str(msg.get("text", ""))
        if t == "error" or re.search(r"(?i)fail|error|invalid|not found|missing", txt):
            ok = False
    if msgs and not ok:
        raise RuntimeError("Install failed (see messages above)")
    if not msgs and "success" not in r.text.lower():
        raise RuntimeError("Install verdict unknown (no success marker)")

    # Launch
    log_cb("Launching dev channel...")
    try:
        lr = _request(session, "POST", f"http://{ip}:8060/launch/dev", log_cb, timeout=10)
        log_cb(f"  LAUNCH={lr.status_code}")
    except Exception as e:
        raise RuntimeError(f"Launch error: {e}")
    # Active app: Roku uses attribute-based entries
    #   <app id="dev" type="appl" version="1.0.0">Channel name</app>
    try:
        ar = _request(session, "GET", f"http://{ip}:8060/query/active-app", log_cb, timeout=5)
        ma = re.search(r'<app\s+id="(?P<id>[^"]*)"[^>]*>(?P<name>[^<]*)</app>', ar.text)
        if ma:
            name = ma.group("name")
            appid = ma.group("id")
            log_cb(f"  Active app: {name} (id={appid})")
            if appid != "dev":
                log_cb("  WARNING: active app is not the dev channel")
        else:
            log_cb(f"  Active app check could not parse response: {ar.text[:200]}")
    except Exception as e:
        log_cb(f"  Active app check failed: {e}")


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Roku Febbox Injector + Deployer")
        self.geometry("760x660")
        self.resizable(True, True)

        # Febbox token
        ttk.Label(self, text="Febbox Token:").pack(anchor="w", padx=10, pady=(10, 2))
        self.token_text = scrolledtext.ScrolledText(self, height=4, wrap=tk.WORD)
        self.token_text.pack(fill="x", padx=10)
        self.token_text.insert("1.0", read_febbox_token())

        ttk.Button(self, text="Replace Febbox Key in Config.brs", command=self.on_replace).pack(pady=6)

        # TMDB key
        ttk.Label(self, text="TMDB Key:").pack(anchor="w", padx=10, pady=(10, 2))
        self.tmdb_text = scrolledtext.ScrolledText(self, height=3, wrap=tk.WORD)
        self.tmdb_text.pack(fill="x", padx=10)
        self.tmdb_text.insert("1.0", read_tmdb_key())

        ttk.Button(self, text="Replace TMDB Key in Config.brs", command=self.on_replace_tmdb).pack(pady=6)

        # Roku discovery
        ttk.Label(self, text="Roku Device:").pack(anchor="w", padx=10, pady=(10, 2))
        row = ttk.Frame(self)
        row.pack(fill="x", padx=10)
        self.roku_combo = ttk.Combobox(row, width=40, state="readonly")
        self.roku_combo.pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="Auto-Find Roku", command=self.on_find).pack(side="left", padx=5)

        # Credentials
        cred = ttk.Frame(self)
        cred.pack(fill="x", padx=10, pady=4)
        ttk.Label(cred, text="User:").pack(side="left")
        self.user_entry = ttk.Entry(cred, width=12)
        self.user_entry.insert(0, DEFAULT_USER)
        self.user_entry.pack(side="left", padx=4)
        ttk.Label(cred, text="Pass:").pack(side="left")
        self.pass_entry = ttk.Entry(cred, width=12, show="*")
        self.pass_entry.insert(0, DEFAULT_PASS)
        self.pass_entry.pack(side="left", padx=4)

        # IP manual entry
        iprow = ttk.Frame(self)
        iprow.pack(fill="x", padx=10, pady=2)
        ttk.Label(iprow, text="Roku IP:").pack(side="left")
        self.ip_entry = ttk.Entry(iprow, width=20)
        self.ip_entry.pack(side="left", padx=4)

        # Buttons
        btns = ttk.Frame(self)
        btns.pack(pady=8)
        ttk.Button(btns, text="Build Package", command=self.on_build).pack(side="left", padx=5)
        ttk.Button(btns, text="Deploy to TV", command=self.on_deploy).pack(side="left", padx=5)
        ttk.Button(btns, text="Build + Deploy", command=self.on_build_deploy).pack(side="left", padx=5)

        # Log
        ttk.Label(self, text="Log:").pack(anchor="w", padx=10, pady=(8, 2))
        self.log_text = scrolledtext.ScrolledText(self, height=16, wrap=tk.WORD, state="disabled")
        self.log_text.pack(fill="both", expand=True, padx=10, pady=(0, 10))

    def log(self, msg):
        if threading.current_thread() is not threading.main_thread():
            self.after(0, self.log, msg)
            return
        self.log_text.configure(state="normal")
        self.log_text.insert(tk.END, str(msg) + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state="disabled")

    def on_replace(self):
        token = self.token_text.get("1.0", tk.END).strip()
        try:
            n = replace_febbox_token(token)
            self.log(f"Replaced Febbox token in {n} location(s).")
            messagebox.showinfo("Success", "Febbox token replaced in Config.brs")
        except Exception as e:
            self.log(f"ERROR: {e}")
            messagebox.showerror("Error", str(e))

    def on_replace_tmdb(self):
        key = self.tmdb_text.get("1.0", tk.END).strip()
        try:
            n = replace_tmdb_key(key)
            self.log(f"Replaced TMDB key in {n} location(s).")
            messagebox.showinfo("Success", "TMDB key replaced in Config.brs")
        except Exception as e:
            self.log(f"ERROR: {e}")
            messagebox.showerror("Error", str(e))

    def on_find(self):
        self.log("Scanning local network for Roku devices...")

        def worker():
            found = discover_roku(progress_cb=lambda kind, ip, found, done, total: (
                self.log(f"  found {ip}") if kind == "found" else
                (self.log(f"  scanned {done}/{total}, {found} found") if (kind == "scan") else None)
            ))
            self.after(0, lambda: self._find_done(found))

        threading.Thread(target=worker, daemon=True).start()

    def _find_done(self, found):
        if not found:
            self.log("No Roku devices found.")
            messagebox.showwarning("Not Found", "No Roku devices found on the network.")
            return
        vals = [f"{ip}  ({name})" for ip, name in found]
        self.roku_combo["values"] = vals
        self.roku_combo.current(0)
        self.ip_entry.delete(0, tk.END)
        self.ip_entry.insert(0, found[0][0])
        self.log("Found: " + ", ".join(vals))

    def _get_ip(self):
        sel = self.roku_combo.get()
        if sel:
            return sel.split()[0]
        return self.ip_entry.get().strip()

    def on_build(self):
        def worker():
            try:
                build_package(self.log)
            except Exception as e:
                self.log(f"BUILD ERROR: {e}")
        threading.Thread(target=worker, daemon=True).start()

    def on_deploy(self):
        ip = self._get_ip()
        user = self.user_entry.get().strip() or DEFAULT_USER
        pw = self.pass_entry.get()
        if not ip:
            messagebox.showerror("Error", "Enter or find a Roku IP first.")
            return

        def worker():
            try:
                deploy(ip, user, pw, self.log)
                self.log("Deploy finished.")
            except Exception as e:
                self.log(f"DEPLOY ERROR: {e}")

        threading.Thread(target=worker, daemon=True).start()

    def on_build_deploy(self):
        ip = self._get_ip()
        user = self.user_entry.get().strip() or DEFAULT_USER
        pw = self.pass_entry.get()
        if not ip:
            messagebox.showerror("Error", "Enter or find a Roku IP first.")
            return

        def worker():
            try:
                build_package(self.log)
                deploy(ip, user, pw, self.log)
                self.log("Build + deploy finished.")
            except Exception as e:
                self.log(f"ERROR: {e}")

        threading.Thread(target=worker, daemon=True).start()


if __name__ == "__main__":
    app = App()
    app.mainloop()
