FROM rust:latest
WORKDIR /app
COPY . .
RUN cargo build --release
CMD ["./target/release/rust-server"]
EXPOSE 8000
