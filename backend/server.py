#!/usr/bin/env python3
"""
Vynix Hosting Panel - Backend
Simple Flask application with SQLite for persistence.
"""
import os
import sqlite3
import hashlib
import secrets
from datetime import datetime
from functools import wraps
from flask import Flask, request, jsonify, session, send_from_directory, redirect
import bcrypt

app = Flask(__name__, static_folder="../public", static_url_path="")
app.secret_key = os.environ.get("SESSION_SECRET", secrets.token_hex(32))

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("DATABASE_URL", os.path.join(BASE_DIR, "../data/vynix.db")).replace("sqlite:", "")
PORT = int(os.environ.get("PANEL_PORT", 6580))
BIND = os.environ.get("PANEL_BIND", "0.0.0.0")

os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
os.makedirs(os.path.join(BASE_DIR, "../servers"), exist_ok=True)

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()
    c.execute("""CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT DEFAULT 'user',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_id INTEGER,
        status TEXT DEFAULT 'stopped',
        software TEXT,
        version TEXT,
        port INTEGER,
        ram_limit INTEGER,
        data_dir TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        server_id INTEGER,
        status TEXT,
        message TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        action TEXT,
        details TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    conn.commit()
    conn.close()

init_db()

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if session.get("role") != "admin":
            return jsonify({"error": "Forbidden"}), 403
        return f(*args, **kwargs)
    return decorated

@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json() or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    if not username or not password:
        return jsonify({"error": "Missing credentials"}), 400
    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    conn.close()
    if not user or not bcrypt.checkpw(password.encode(), user["password_hash"].encode()):
        return jsonify({"error": "Invalid credentials"}), 401
    session["user_id"] = user["id"]
    session["username"] = user["username"]
    session["role"] = user["role"]
    conn = get_db()
    conn.execute("INSERT INTO audit_logs (user_id, action, details) VALUES (?, ?, ?)",
                 (user["id"], "login", "Successful login"))
    conn.commit()
    conn.close()
    return jsonify({"success": True, "username": user["username"], "role": user["role"]})

@app.route("/api/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify({"success": True})

@app.route("/api/me")
@login_required
def me():
    return jsonify({
        "id": session["user_id"],
        "username": session["username"],
        "role": session["role"]
    })

@app.route("/api/dashboard")
@login_required
def dashboard():
    conn = get_db()
    rows = conn.execute("SELECT status, COUNT(*) as count FROM servers GROUP BY status").fetchall()
    stats = {"total": 0, "running": 0, "stopped": 0, "starting": 0, "stopping": 0}
    for r in rows:
        stats[r["status"]] = r["count"]
        stats["total"] += r["count"]
    users = conn.execute("SELECT COUNT(*) as c FROM users").fetchone()["c"]
    conn.close()
    return jsonify({
        "servers": stats,
        "users": users,
        "note": "Resource metrics and live console require a node agent with Docker. Showing database state."
    })

@app.route("/api/servers", methods=["GET"])
@login_required
def list_servers():
    conn = get_db()
    if session.get("role") == "admin":
        rows = conn.execute("SELECT * FROM servers").fetchall()
    else:
        rows = conn.execute("SELECT * FROM servers WHERE owner_id = ?", (session["user_id"],)).fetchall()
    conn.close()
    return jsonify([dict(r) for r in rows])

@app.route("/api/servers", methods=["POST"])
@login_required
def create_server():
    data = request.get_json() or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "Name required"}), 400
    software = data.get("software", "vanilla")
    version = data.get("version", "1.20.1")
    port = int(data.get("port", 25565))
    ram = int(data.get("ram", 2048))
    data_dir = os.path.join(BASE_DIR, "../servers", str(int(datetime.now().timestamp())))
    os.makedirs(data_dir, exist_ok=True)
    conn = get_db()
    cur = conn.execute(
        "INSERT INTO servers (name, owner_id, software, version, port, ram_limit, data_dir, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (name, session["user_id"], software, version, port, ram, data_dir, "stopped")
    )
    server_id = cur.lastrowid
    conn.execute("INSERT INTO jobs (type, server_id, status, message) VALUES (?, ?, ?, ?)",
                 ("create", server_id, "completed", "Server record created"))
    conn.commit()
    conn.close()
    return jsonify({"id": server_id, "message": "Server created. Full installation requires Docker node agent."})

@app.route("/api/health")
def health():
    return jsonify({"status": "ok", "time": datetime.utcnow().isoformat()})

@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def catch_all(path):
    if path and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)
    return send_from_directory(app.static_folder, "index.html")

if __name__ == "__main__":
    print(f"Vynix Panel listening on {BIND}:{PORT}")
    app.run(host=BIND, port=PORT, debug=False)
