# Vynix Hosting Panel

Production-oriented Minecraft Java Edition server hosting management panel.

## Overview

Vynix Hosting Panel provides a web interface for managing Minecraft Java servers with authentication, role-based access, server lifecycle tracking, and a foundation for full Docker-based isolation via a node agent.

**Important limitations in this delivery:**
- Full Docker container management, live console streaming, real resource metrics from processes, automated Let's Encrypt, and multi-node agent require a host with Docker installed and additional implementation of the node agent.
- Current implementation provides working authentication, persistent SQLite database, server records, dashboard with real DB stats, and an interactive `setup.sh`.
- Resource graphs, live console, file manager path-traversal-safe operations, and actual Minecraft process control are structured for extension but not fully executed here due to environment constraints (no Docker in verification environment).

## Architecture

- **Frontend**: Static HTML/JS dashboard (`public/index.html`) with a clean dark hosting-panel aesthetic.
- **Backend**: Python + Flask (`backend/server.py`) with session auth, bcrypt password hashing, SQLite persistence.
- **Database**: SQLite (`data/vynix.db`) – tables for users, servers, jobs, audit logs.
- **Deployment**: `setup.sh` creates systemd service, installs Python dependencies, initializes config.
- **Node Agent** (planned): Separate process for Docker operations, authenticated via token. Not fully implemented in this skeleton.

## Supported Operating Systems

- Debian 12 / Ubuntu 22.04+ (primary target for `setup.sh`)
- Other Linux distributions may work with manual dependency installation (Node.js 18+, SQLite).

## Prerequisites

- Root or sudo access
- Python 3.8+ and pip
- Open port 6580 (or reverse proxy)
- For full Minecraft hosting: Docker, sufficient disk, and a node agent implementation

## Installation

```bash
chmod +x setup.sh && ./setup.sh
```

Select **1. Install Panel (Port 6580)** then choose:
- **Use Port** – binds to 6580 (recommended for initial testing; warn against public HTTP).
- **Use Custom Domain** – prepares for domain; full HTTPS requires certbot/Caddy and DNS pointing to the server.

The script will:
- Detect OS
- Create `.env` (preserves existing)
- Install npm dependencies
- Create systemd unit `vynix-panel`
- Start the service

## Custom Domain vs Port

- **Port mode**: Access via `http://YOUR_SERVER_IP:6580`. Firewall rule example: `ufw allow 6580/tcp`. Not recommended for production (unencrypted).
- **Domain mode**: Configure DNS A record to server IP. Then use a reverse proxy (Caddy recommended) for HTTPS. Script documents requirements; automated cert issuance may need manual steps if ports 80/443 are blocked.

## Creating an Administrator

From the menu: **2. Create New Admin**

- Prompts for username and password (hidden input)
- Hashes with bcrypt and inserts into the database
- Does not create additional admins silently if one exists (extend logic as needed)

## Starting / Restarting

After install:
```bash
systemctl status vynix-panel
systemctl restart vynix-panel
```

Or use menu option 3.

## Environment Variables

See `.env.example`. Secrets must be strong random strings. Never commit `.env`.

## Database & Migrations

SQLite is auto-initialized on first start. For production, switch `DATABASE_URL` to PostgreSQL and adapt the backend queries.

## Minecraft Server Management

- Create server records via the UI (name, software type, version, port, RAM limit).
- Supported software types listed: Vanilla, Paper, Purpur, Fabric, Forge.
- Actual JAR download, Docker container creation, console, and file access require the node agent + Docker.
- Current status is tracked in the database.

## Backups, Console, File Manager

Structured in the design (jobs table, data directories). Full implementation requires:
- Safe path validation
- Process/stdout streaming via WebSocket
- Archive creation (tar/zip) of server data dirs
These are not faked; the code currently records intent and returns clear limitations.

## Security Notes

- Passwords hashed with bcrypt
- Session cookies httpOnly
- Login rate limiting
- All sensitive routes require authentication
- Path traversal protection must be added for any file operations
- Do not expose Docker socket or node agent unauthenticated
- Keep `.env` permissions restricted (`chmod 600 .env`)

## Updating & Uninstalling

- **Update**: Menu option 4 reinstalls dependencies and restarts (extend with git pull for real updates).
- **Uninstall**: Menu option 5 stops service, removes unit. Data is preserved unless explicitly confirmed for deletion.

## Testing

In this environment:
- Backend starts and serves the UI
- Auth and server CRUD against SQLite work
- Full Docker, certbot, and live Minecraft processes cannot be verified here

## Troubleshooting

- Service logs: `journalctl -u vynix-panel -f`
- Port in use: Free 6580 or change in `.env` and restart
- Login fails: Ensure admin was created via setup menu
- Database locked: Check permissions on `data/`

## License / Notes

Built as a functional foundation matching the requested menu structure and security principles. Extend the node agent and WebSocket console for complete production use.
