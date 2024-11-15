use actix_files as fs;
use actix_web::{App, HttpServer};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            // Serve static files from /var/www/assets/dltc
            .service(fs::Files::new("/", "/var/www/assets/dialectica").index_file("index.html"))
    })
    .bind("127.0.0.1:8000")? // Port matches NGINX config
    .run()
    .await
}

