# Deployment Checklist

## First-Time Setup

1. Run `./deploy-secure.sh` — prompts you to edit `.env`, then validates and deploys
2. Access NPM GUI via SSH tunnel: `ssh -L 8080:localhost:81 user@server`
3. Configure proxy hosts in NPM for nginx-static and filebrowser
4. Change FileBrowser admin password
5. **Save the `ASSETS_SIGNING_SECRET`** — Portal needs the same value

## Redeployment (Config Changes)

1. Make changes to config files
2. Run `./deploy-secure.sh` (restarts containers and runs tests)
3. Verify: `docker exec nginx-static cat /etc/nginx/conf.d/default.conf`
4. *(Optional)* Purge CDN cache (see below)

## Quick Deploy Script

```bash
./deploy-secure.sh
```

Generates secret, updates `.env`, restarts containers, runs tests.

## Verify Signed URLs Working

```bash
# Should return 403 (no signature)
curl -I https://assets.yourdomain.com/any-file.pdf

# Should return 200 (valid signature)
# Use deploy-secure.sh output or generate manually
```

## CDN Cache Purge (Optional)

If using Cloudflare or similar CDN, purge cache after:
- Enabling/disabling signed URLs
- Changing security headers
- Any nginx config changes

**Cloudflare:** Dashboard → Caching → Configuration → Purge Everything

## Rollback

1. Restore old `nginx-static/default.conf.template`
2. `docker compose up -d`
