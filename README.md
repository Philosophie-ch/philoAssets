# Philosophie.ch's Assets

Dockerized services to provide a management system for Philosophie.ch's assets.


## Explanation

The tech stack here is composed of the following elements, each one is an individual docker container:

- **Nginx Proxy Manager**: provides a simple GUI interface to configure nginx. Features:
    + SSL certificates management: easy setup of new certificates; auto-renewals
    + Proxy Hosts (reverse proxy setup): easy setup of proxy hosts for apps running locally in the back
    + Simple user management system

- **FileBrowser**: provides a simple GUI interface to manage static files. Features:
    + Easy uploads and downloads
    + User management system

- **Dialectica Server**: simple backend server to provide custom routing for Dialectica's assets. Features:
    + Backend only, no GUI
    + Written in Rust for performance
    + Source code and Dockerfile at `dialectica-server`


**NOTE**: All data is decoupled from this tech stack. This means that everything you configure (users in the apps, SSL certs, actual asset files) will persist even if you kill the containers. This implies you need a manual configuration step the first time you run this, see below.


## Installation

1. Provision a Linux server with `git` and `docker` installed.
2. Clone this project in your server
3. Create a `.env` file and fill the required environment variables:
    + `ASSETS_DIR`: path to your assets directory. Can be anywhere, but you might want to mount a dedicated volume for this
    + `UID`: if running as non-root, the user ID of the non-root user; get it with `id ${USER}`
    + `GID`: if running as non-root, the group ID of the non-root user; get it with `id ${USER}`
4. Create an empty file for FileBrowser's database: `touch filebrowser/database.db`
    - **IMPORTANT**! Otherwise the FileBrowser container will fail as docker compose doesn't correctly create this as a file (but as a directory, if no file is found)
5. Run `docker compose up`
6. Go to `http://${your_server_ip}:81` to enter Nginx Proxy Manager GUI
    + Default credentials are `admin@example.ch` and `changeme`
    + Create a first admin user and **change the password**
    + Configure static file serving at your `ASSETS_DIR`
    + Go to `Hosts >> Proxy hosts` and configure:
        - http for `filebrowser` at port `80`
        - http for `dialectica-server` at port `8000`
        - Recommended: enable caching, block of common exploits, and in SSL, force SSL and HTTP/2
7. Go to the URL assigned to `filebrowser`
    + Login for the first time with `admin` and `admin`
    + **Change the password of the admin user** and create more users as needed