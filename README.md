# FreeCP Server

> **Free, open-source Docker-powered hosting control panel for Laravel applications.**
> The self-hosted alternative to cPanel — built for the modern stack.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-5.0%2B-blue)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-required-blue)](https://docker.com)

**Author:** [Rifat](https://rifatxtra.com) · [GitHub](https://github.com/rifatxtra)
**Panel:** [freecp.rifatxtra.com](https://freecp.rifatxtra.com)

---

## What is FreeCP?

FreeCP lets you run a Laravel hosting reseller business on a single VPS. Each client gets a fully isolated Docker container with hard resource limits, automated GitHub Actions deployments, and a single `freecp` command to manage everything.

**Key features:**

- 🐳 Full Docker isolation per client (CPU, RAM, storage, bandwidth)
- ⚡ Laravel Octane (FrankenPHP) support for Ultra plan
- 🔄 GitHub Actions CI/CD — rsync-based zero-downtime deployments
- 🔒 Security hardened — no-new-privileges, capability dropping, network isolation
- 📊 Dynamic storage quota — container + database size combined
- 🌐 Automatic Nginx vhost + SSL (Let's Encrypt) per domain
- 👥 Supervisor manages queues and scheduler per client
- 💾 Optional backup VPS with single-command full restore
- 🖥️ Web panel ([freecp-panel](https://github.com/rifatxtra/freecp-panel)) — coming soon

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Main VPS (8GB RAM)                 │
│                                                 │
│  ┌──────────┐  ┌────────┐  ┌────────────────┐  │
│  │  Nginx   │  │ Redis  │  │    MariaDB     │  │
│  │ (Proxy)  │  │  1GB   │  │      2GB       │  │
│  └────┬─────┘  └────────┘  └────────────────┘  │
│       │                                         │
│  ┌────┴────────────────────────────────────┐    │
│  │       Client Container Pool (4.5GB)     │    │
│  │  ┌──────────┐ ┌──────────┐ ┌─────────┐ │    │
│  │  │  client1 │ │  client2 │ │  ultra  │ │    │
│  │  │  (lite)  │ │(standard)│ │(octane) │ │    │
│  │  └──────────┘ └──────────┘ └─────────┘ │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

---

## Hosting Plans

| Plan     | Price     | RAM (Res/Max) | CPU  | Storage | Bandwidth | Peak Users |
| -------- | --------- | ------------- | ---- | ------- | --------- | ---------- |
| Lite     | 250 BDT   | 128MB / 512MB | 0.25 | 8 GB    | 100 GB    | 20         |
| Standard | 550 BDT   | 256MB / 1GB   | 0.50 | 15 GB   | 250 GB    | 60         |
| Plus     | 950 BDT   | 512MB / 2GB   | 1.00 | 30 GB   | 500 GB    | 150        |
| Ultra    | 1,850 BDT | 1GB / 4GB     | 2.00 | 50 GB   | 1 TB      | 400+       |

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/rifatxtra/freecp-server/main/bash/install.sh | bash
```

Configure, then initialize:

```bash
nano /opt/freecp/config/freecp.conf
freecp init-server
freecp setup-smtp
```

---

## Quick Start

```bash
# Create a client
freecp create-client example.com lite php83

# Provision SSL (after DNS is pointed to this server)
freecp provision-ssl example.com

# Check status
freecp status-client example.com

# View all clients
freecp list-clients
```

---

## All Commands

```bash
# Server
freecp init-server
freecp setup-smtp
freecp check-server-usage
freecp list-php
freecp setup-backup <vps-ip>
freecp backup-server
freecp restore-server
freecp list-backups-server

# Client
freecp create-client <domain> <plan> [php]
freecp delete-client <domain> [--force]
freecp suspend-client <domain>
freecp unsuspend-client <domain>
freecp upgrade-client <domain> <plan>
freecp resize-storage <domain> <size>
freecp list-clients
freecp status-client <domain>
freecp check-usage <domain>
freecp restart-client <domain>
freecp rebuild-client <domain>
freecp maintenance-client <domain> on|off
freecp set-client-email <domain> <email>
freecp logs-client <domain> [type] [--follow]
freecp reset-bandwidth <domain>
freecp backup-client <domain>
freecp restore-client <domain>
freecp list-backups <domain>

# Domains & SSL
freecp add-domain <domain> <addon>
freecp remove-domain <domain> <addon>
freecp list-domains <domain>
freecp provision-ssl <domain>
freecp renew-ssl <domain>

# Database
freecp create-db <domain> <dbname>
freecp delete-db <domain> <dbname>
freecp list-dbs <domain>

# PHP / Env / SSH / Redis
freecp switch-php <domain> <version>
freecp update-env <domain> KEY VALUE
freecp create-env <domain>
freecp edit-env <domain>
freecp read-key <domain>
freecp regenerate-key <domain>
freecp flush-redis <domain>
```

---

## Repository Structure

```
freecp-server/
  bash/          # Shell-based engine (current)
  laravel/       # Laravel API + panel engine (coming soon)
  README.md
```

---

## License

MIT — see [LICENSE](LICENSE)
