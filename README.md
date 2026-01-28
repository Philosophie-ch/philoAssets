# Philosophie.ch's Assets Tech Stack

Dockerized services to provide a secure management system for Philosophie.ch's assets.

## Explanation

The tech stack here is composed of the following elements, each one running in an individual docker container:

- **Nginx Proxy Manager**: provides a simple GUI interface to configure nginx. Features:
    + SSL certificates management: easy setup of new certificates; auto-renewals
    + Proxy Hosts (reverse proxy setup): easy setup of proxy hosts for apps running locally in the back
    + Caching, security headers, and other features

- **Nginx Static**: serves static files with signed URL validation. Features:
    + **Signed URLs required** — all requests must include valid `md5` hash and `expires` timestamp
    + Security headers block search engine indexing (X-Robots-Tag)
    + Fast and efficient serving via nginx

- **FileBrowser**: provides a simple GUI interface to manage static files. Features:
    + Easy uploads and downloads
    + User management system
    + REST API for programmatic uploads

- **Notes**:
    + The container's ports are not exposed to the internet, nor mapped to the server's ports (except for the NPM ports). Instead, they are exposed to the host machine, and then proxied by Nginx Proxy Manager. This is a more secure setup and it is recommended to keep it this way.
    + All data is decoupled from this tech stack. This means that everything you configure (users in the apps, SSL certs, actual asset files) will persist even if you kill the containers. This implies you need a manual configuration step the first time you run this and back them up on your own, see below.


## Installation

1. Provision a Linux server with `git` and `docker` installed. Open the ports `80` and `443` for the server

2. Clone this project in your server

3. Run the deployment script:
    ```bash
    ./deploy-secure.sh
    ```
    The script will:
    + Create `.env` from `.env.example` (prompts you to edit it)
    + Validate required variables:
        - `ASSETS_DIR`: path to your assets directory (can be anywhere, but you might want a dedicated volume)
        - `UID`: user ID of the non-root user running containers; get it with `id -u`
        - `GID`: group ID of the non-root user; get it with `id -g`
    + Generate `ASSETS_SIGNING_SECRET` for signed URLs
    + Create `filebrowser/database.db`
    + Start containers and run validation tests

4. Using a secure method, bind `localhost:81` on your server to your local machine:
    ```bash
    ssh -L 8080:localhost:81 {server_user}@{server_ip}
    ```
    Then open a browser and go to `http://localhost:8080` for the Nginx Proxy Manager GUI.

5. Once you're in the GUI:
    + Default credentials are `admin@example.ch` and `changeme`
    + Create a first admin user and **change the email and password**
    + Go to `Hosts >> Proxy hosts` and configure:
        - http for `nginx-static` at port `80`
        - http for `filebrowser` at port `80`
        - Recommended for all above: enable caching, block of common exploits, and in SSL, force SSL and HTTP/2

6. Go to the URL assigned to `filebrowser`
    + Login for the first time with `admin` and `admin`
    + **Change the password of the admin user**

7. **Save the `ASSETS_SIGNING_SECRET`** from the deploy script output — any client application needs this same value to generate valid signed URLs.

See [docs/deployment.md](docs/deployment.md) for detailed checklist.


## Signed URL Format

All asset requests require signed URLs:

```
https://assets.mydomain.com/path/to/file.pdf?md5=HASH&expires=TIMESTAMP
```

- `md5`: Base64URL-encoded MD5 hash of `{expires}{uri} {secret}`
- `expires`: Unix timestamp (seconds since epoch)
- Default expiry: 24 hours (compatible with CDN caching)

### Response Codes

| Code | Meaning |
|------|---------|
| 200 | Valid signature, file served |
| 403 | Invalid or missing signature |
| 410 | Expired signature |
| 404 | File not found |


## Example

1. Create two subdomains:
    + `assets.mydomain.com`
    + `fb-assets.mydomain.com`

2. Run `./deploy-secure.sh` and configure NPM proxy hosts as explained above.

3. Use FileBrowser to upload files. Client applications must generate signed URLs — direct URLs will return 403.


## Maintenance

### Redeployment (Config Changes)

After making changes to config files (e.g., `nginx-static/default.conf.template`):

```bash
./redeploy.sh
```

This script keeps the existing signing secret and restarts containers with the new config. It also runs validation tests to ensure everything works.

After redeployment, remember to **purge your CDN cache** (e.g., Cloudflare Dashboard → Caching → Purge Everything).

### Health Check

Run without redeploying to verify everything is working:

```bash
./check.sh
```

Checks: env vars, Docker containers, nginx config, signed URL validation.

### Backups

- **Backups**: make sure to backup, at the very least, your assets directory, as the rest of the stack is easily reproducible and the manual configurations are easy to set up again.
    + You can do this by running `rsync -avz {server_user}@{server_ip}:{ASSETS_DIR} /path/to/backup` from your backup machine
    + If you want to backup the Nginx Proxy Manager configurations, you can do so by backing up the `nginx-proxy-manager` folder, which is created in the same directory as this project, in your server
    + If you want to backup the FileBrowser configurations, you can do so by backing up the `filebrowser` folder, which is created in the same directory as this project, in your server


## Troubleshooting

- You can set up a simple cronjob to dump the docker compose logs every night, for example, to a file. This will help you diagnose any issues that might arise. For example, you can add this to your crontab:
    + `0 0 * * * docker compose logs --no-color > /path/to/logs/docker-compose-$(date +\%Y\%m\%d).log 2>&1`
    + To do so, run `crontab -e` and add the line above. This will run the command every night at midnight and save the logs to a file with the date in the name
