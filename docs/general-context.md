# PhiloAssets - Project Briefing

## Overview

PhiloAssets is a containerized static asset management and serving system for Philosophie.ch. It provides infrastructure for storing, managing, and efficiently serving static files (PDFs, images, videos, audio) through a multi-container Docker architecture.

## Architecture

The system consists of three Docker containers communicating over a private bridge network (`philo-assets-network`):

```
Internet (ports 80, 443)
         │
         ▼
┌─────────────────────────────────────┐
│     Nginx Proxy Manager (NPM)       │
│  • Reverse proxy & SSL termination  │
│  • Admin GUI on port 81             │
│  • Let's Encrypt integration        │
└─────────────┬───────────────────────┘
              │
    ┌─────────┼─────────┬─────────────┐
    ▼         ▼         ▼             │
┌────────┐ ┌────────┐ ┌─────────────┐ │
│ Nginx  │ │ File   │ │   Assets    │ │
│ Static │ │Browser │ │   Volume    │ │
│        │ │        │ │             │ │
│port 80 │ │  GUI   │ │ /ASSETS_DIR │ │
└────────┘ └────────┘ └─────────────┘ │
```

### Services

| Service | Purpose | Technology |
|---------|---------|------------|
| **nginx-proxy-manager** | Entry point, reverse proxy, SSL management | jc21/nginx-proxy-manager |
| **nginx-static** | High-performance static file serving | nginx:latest |
| **filebrowser** | Web-based file management interface | filebrowser/filebrowser |

## Directory Structure

```
philoAssets/
├── docker-compose.yml          # Container orchestration
├── .env                        # Environment configuration
├── .env.example                # Environment template
├── README.md                   # Setup and usage guide
│
├── nginx-static/
│   └── default.conf.template   # Nginx config template (envsubst processed)
│
├── filebrowser/
│   └── database.db             # FileBrowser state (SQLite)
│
├── nginx-proxy-manager/
│   ├── data/                   # NPM configuration
│   └── letsencrypt/            # SSL certificates
│
├── assets/                     # Static file storage
│
└── docs/                       # Documentation
    └── general-context.md      # This file
```

## Key Configuration Files

### docker-compose.yml

Defines all three services with their:
- Container images and build contexts
- Port mappings (only NPM exposes ports publicly)
- Volume mounts for data persistence
- Network configuration
- User/group IDs for file permissions

### .env

Environment variables consumed by docker-compose:

| Variable | Purpose |
|----------|---------|
| `ASSETS_DIR` | Absolute path to the assets directory |
| `UID` | User ID for container processes |
| `GID` | Group ID for container processes |
| `ASSETS_SIGNING_SECRET` | Shared secret for signed URL validation |

### nginx-static/default.conf.template

Configures the static file server:
- **Signed URL validation** using nginx `secure_link` module
- MIME type mappings for all supported file types
- Security headers (X-Content-Type-Options, X-XSS-Protection, X-Robots-Tag)
- UTF-8 charset encoding

## Network Architecture

- All containers connect to `philo-assets-network` (Docker bridge)
- Only NPM exposes ports to the host (80, 443, 81)
- Internal services communicate via container names
- NPM routes external requests to appropriate backends

## Data Persistence

| Data | Location | Persistence |
|------|----------|-------------|
| Static files | `${ASSETS_DIR}` | Host filesystem |
| NPM config | `./nginx-proxy-manager/data/` | Host filesystem |
| SSL certs | `./nginx-proxy-manager/letsencrypt/` | Host filesystem |
| FileBrowser DB | `./filebrowser/database.db` | Host filesystem |

Containers are ephemeral; all persistent data lives on the host.

## Deployment

### Prerequisites

- Linux host with Git and Docker installed
- Domain names configured to point to the server
- Ports 80 and 443 available

### Setup Steps

1. Clone the repository
2. Copy `.env.example` to `.env` and configure variables
3. Create required directories and set permissions
4. Run `docker compose up -d`
5. Access NPM admin (port 81) via SSH tunnel
6. Configure proxy hosts for each domain in NPM
7. Set up FileBrowser admin credentials

### Typical Domain Configuration

| Domain | Backend Service | Purpose |
|--------|-----------------|---------|
| `assets.domain.com` | nginx-static | Signed URL file access |
| `fb-assets.domain.com` | filebrowser | File management |

## Technology Stack

- **Container Runtime**: Docker with Docker Compose
- **Reverse Proxy**: Nginx Proxy Manager (Node.js-based)
- **Static Server**: Nginx
- **File Manager**: FileBrowser
- **SSL**: Let's Encrypt (auto-managed by NPM)

## Supported File Types

The nginx-static service is configured to serve:

- **Images**: jpeg, jpg, png, gif, webp, svg, svgz
- **Video**: mp4, webm, mov, ogg
- **Audio**: mp3, m4a, oga, wav
- **Documents**: pdf, html, htm, css, js

## Security Considerations

- **Signed URLs required**: All asset requests must include valid `md5` and `expires` query parameters
- NPM admin interface (port 81) should only be accessed via SSH tunnel
- Security headers prevent MIME sniffing and XSS attacks
- X-Robots-Tag header blocks search engine indexing
- robots.txt in assets directory blocks crawlers
- SSL/HTTPS enforced through NPM configuration
- File permissions managed via UID/GID environment variables
- Asset volumes for `nginx-static` are mounted read-only (serving-only access)
- Asset volumes for FileBrowser are mounted read-write for upload and management

## Signed URL Format

Assets are accessed via time-limited signed URLs:

```
https://assets.domain.com/path/to/file.pdf?md5=HASH&expires=TIMESTAMP
```

- `md5`: Base64URL-encoded MD5 hash of `{expires}{uri} {secret}`
- `expires`: Unix timestamp (seconds since epoch)
- Default expiry: 24 hours (compatible with Cloudflare CDN caching)

Client applications generate these URLs using a shared secret (`ASSETS_SIGNING_SECRET`).

### Response Codes

| Code | Meaning |
|------|---------|
| 200 | Valid signature, file served |
| 403 | Invalid or missing signature |
| 410 | Expired signature |
| 404 | File not found |

## Common Operations

### Starting/Stopping Services

```bash
docker compose up -d      # Start all services
docker compose down       # Stop all services
docker compose restart    # Restart all services
```

### Viewing Logs

```bash
docker compose logs -f              # All services
docker compose logs -f nginx-static # Specific service
```

### Managing Files

- Use FileBrowser web interface for upload/download/management
- Or directly access the `${ASSETS_DIR}` directory on the host

## Further Reading

- [README.md](../README.md) - Detailed setup instructions
- [Nginx Proxy Manager Docs](https://nginxproxymanager.com/)
- [FileBrowser Docs](https://filebrowser.org/)
