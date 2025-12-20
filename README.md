# Philosophie.ch's Assets Tech Stack

Dockerized services to provide a management system for Philosophie.ch's assets.


## Explanation

The tech stack here is composed of the following elements, each one running in an individual docker container:

- **Nginx Proxy Manager**: provides a simple GUI interface to configure nginx. Features:
    + SSL certificates management: easy setup of new certificates; auto-renewals
    + Proxy Hosts (reverse proxy setup): easy setup of proxy hosts for apps running locally in the back
    + Caching, security headers, and other features

- **Nginx Static**: serves static files. Features:
    + Fast and efficient
    + Easy to configure
    + Auto-reloads when files change

- **FileBrowser**: provides a simple GUI interface to manage static files. Features:
    + Easy uploads and downloads
    + User management system

- **Notes**:
    + The container's ports are not exposed to the internet, nor mapped to the server's ports (except for the NPM ports). Instead, they are exposed to the host machine, and then proxied by Nginx Proxy Manager. This is a more secure setup and it is recommended to keep it this way.
    + All data is decoupled from this tech stack. This means that everything you configure (users in the apps, SSL certs, actual asset files) will persist even if you kill the containers. This implies you need a manual configuration step the first time you run this and back them up on your own, see below.


## Installation

1. Provision a Linux server with `git` and `docker` installed. Open the ports `80` and `443` for the server

2. Clone this project in your server

3. Create a `.env` file and fill the required environment variables:
    + `ASSETS_DIR`: path to your assets directory. Can be anywhere, but you might want to mount a dedicated volume for this. Make sure that the user running the containers has read/write permissions to this directory
    + `UID`: if running as non-root, the user ID of the non-root user; get it with `id ${USER}`
    + `GID`: if running as non-root, the group ID of the non-root user; get it with `id ${USER}`

4. Create certain files and folders with the user that will run the containers, to manage permissions correctly
    + An empty file for FileBrowser's database: `touch filebrowser/database.db`
    **IMPORTANT**! If you don't do this, docker compose will create `filebrowser/database.db` as a folder, which will cause issues to FileBrowser. If you forgot to do this, it's enough to just delete `filebrowser/database.db` and create an empty file as above

5. Run `docker compose up -d`

6. Using a secure method, bind `localhost:81` on your server to your local machine, and open a browser. For example:
    + `ssh -L 8080:localhost:81 {server_user}@{server_ip}`
    + Then open a browser and go to `http://localhost:8080`, which will enter the Nginx Proxy Manager GUI
    + NOTE: you can also use a VPN to access the server, or open the ports `81` in the server and access them directly. In any case, it is NOT recommended to expose port `81` (or wherever NPM is running) to the internet

7. Once you're in the GUI:
    + Default credentials are `admin@example.ch` and `changeme`
    + Create a first admin user and **change the email and password**
    + Go to `Hosts >> Proxy hosts` and configure:
        - http for `nginx-static` at port `80`
        - http for `filebrowser` at port `80`
        - Recommended for all above: enable caching, block of common exploits, and in SSL, force SSL and HTTP/2
        - NPM will allow you to create a SSL certificate for each one during the setup, and then these will be auto-renewed

8. Go to the URL assigned to `filebrowser`
    + Login for the first time with `admin` and `admin`
    + **Change the password of the admin user** and create more users as needed
    + Now you can upload files, rename them, delete them, etc., and you'll see the changes directly reflected in the files served by `nginx-static` server


## Example

1. Create two subdomains:
    + `assets.mydomain.com`
    + `fb-assets.mydomain.com`

2. Go through steps 1 to 6 as explained above. On step 7, in your own Nginx Proxy Manager, configure each subdomain to point to the respective service:
    + `assets.mydomain.com` → `nginx-static`
    + `fb-assets.mydomain.com` → `filebrowser`

3. You are now set. Use FileBrowser to upload files (as explained in step 8 above), and then you'll automatically get matching URLs for them via the static server. For example, if you upload a file `my-file.pdf` in FileBrowser, it will be available on the internet as `assets.mydomain.com/my-file.pdf`.


## Maintenance

- **Backups**: make sure to backup, at the very least, your assets directory, as the rest of the stack is easily reproducible and the manual configurations are easy to set up again.
    + You can do this by running `rsync -avz {server_user}@{server_ip}:{ASSETS_DIR} /path/to/backup` from your backup machine
    + If you want to backup the Nginx Proxy Manager configurations, you can do so by backing up the `nginx-proxy-manager` folder, which is created in the same directory as this project, in your server
    + If you want to backup the FileBrowser configurations, you can do so by backing up the `filebrowser` folder, which is created in the same directory as this project, in your server


## Troubleshooting

- You can set up a simple cronjob to dump the docker compose logs every night, for example, to a file. This will help you diagnose any issues that might arise. For example, you can add this to your crontab:
    + `0 0 * * * docker compose logs --no-color > /path/to/logs/docker-compose-$(date +\%Y\%m\%d).log 2>&1`
    + To do so, run `crontab -e` and add the line above. This will run the command every night at midnight and save the logs to a file with the date in the name
