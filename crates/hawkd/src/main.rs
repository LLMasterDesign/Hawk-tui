// ▛▞// HAWKD :: Spine (broadcast + ingest + grpc watch)
// @ctx ⫸ [accept.broadcast.broadcastloop]
use anyhow::Context;
use clap::{Parser, ValueEnum};

use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use hawk_core::HawkFrame;
use time::OffsetDateTime;

#[cfg(unix)]
use std::os::unix::net::{UnixListener, UnixStream};

mod grpc_health;
mod systemd;
mod unix_ingest;

// :: ∎

// ▛▞// cli :: hawkd.cli
// @ctx ⫸ [cli.broadcast.mtls]
#[derive(Debug, Clone, Parser)]
#[command(name = "hawkd", version, about = "hawkd: Unix socket spine for HawkFrames")]
struct Cli {
    /// Broadcast socket path (hawk UI connects here).
    #[arg(long, default_value = "/tmp/hawk.sock")]
    socket_path: PathBuf,

    /// Remove existing broadcast socket file before binding.
    #[arg(long, default_value_t = true)]
    overwrite: bool,

    /// Optional ingest socket path (publishers connect here).
    /// If omitted, ingest socket is disabled.
    #[arg(long)]
    ingest_path: Option<PathBuf>,

    /// Remove existing ingest socket file before binding.
    #[arg(long, default_value_t = true)]
    ingest_overwrite: bool,

    /// If true, parse errors terminate stdin and ingest sources.
    #[arg(long, default_value_t = false)]
    strict: bool,

    /// Input source for stdin.
    /// none means do not read stdin.
    #[arg(long, value_enum, default_value = "stdin")]
    source: Source,

    /// Write a comment banner to new sockets.
    #[arg(long, default_value_t = true)]
    client_banner: bool,

    /// gRPC health watch spec (repeatable).
    /// format: endpoint,service,id
    #[arg(long = "watch", value_parser = grpc_health::parse_watch_spec)]
    watches: Vec<grpc_health::WatchSpec>,

    /// systemd unit watch specs (repeatable).
    /// format: unit,id
    #[arg(long = "unit", value_parser = systemd::parse_unit_spec)]
    units: Vec<systemd::UnitSpec>,

    /// gRPC TLS mode for all watches.
    #[arg(long, value_enum, default_value = "off")]
    grpc_tls_mode: grpc_health::GrpcTlsMode,

    /// CA certificate PEM path (required for Tls or Mtls).
    #[arg(long)]
    grpc_ca: Option<PathBuf>,

    /// Domain name override for TLS verification (SNI).
    #[arg(long)]
    grpc_domain: Option<String>,

    /// Client certificate PEM (required for Mtls).
    #[arg(long)]
    grpc_cert: Option<PathBuf>,

    /// Client private key PEM (required for Mtls).
    #[arg(long)]
    grpc_key: Option<PathBuf>,

    /// Per-entity stale TTL for systemd sources.
    #[arg(long, default_value_t = 3600)]
    systemd_ttl_stale_s: i64,

    /// Per-entity dead TTL for systemd sources.
    #[arg(long, default_value_t = 21600)]
    systemd_ttl_dead_s: i64,

    /// Per-entity stale TTL for gRPC watch sources.
    #[arg(long, default_value_t = 3600)]
    grpc_ttl_stale_s: i64,

    /// Per-entity dead TTL for gRPC watch sources.
    #[arg(long, default_value_t = 21600)]
    grpc_ttl_dead_s: i64,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Source {
    Stdin,
    None,
}
// :: ∎

// ▛▞// main :: hawkd.main
// @ctx ⫸ [accept.broadcast.broadcastloop]
fn main() -> anyhow::Result<()> {
    #[cfg(not(unix))]
    {
        anyhow::bail!("hawkd requires a unix platform (WSL, Linux, macOS) for Unix sockets");
    }

    #[cfg(unix)]
    {
        let cli = Cli::parse();

        if cli.overwrite {
            let _ = std::fs::remove_file(&cli.socket_path);
        }

        let listener = UnixListener::bind(&cli.socket_path)
            .with_context(|| format!("bind broadcast socket at {:?}", cli.socket_path))?;

        let clients: Arc<Mutex<Vec<UnixStream>>> = Arc::new(Mutex::new(Vec::new()));

        // Central spine channel: producers emit bytes, broadcaster writes to UI clients.
        let (spine_tx, spine_rx) = std::sync::mpsc::channel::<Vec<u8>>();

        // Broadcast accept loop.
        {
            let clients = Arc::clone(&clients);
            let banner = cli.client_banner;
            std::thread::spawn(move || accept_loop(listener, clients, banner));
        }

        // Optional ingest socket.
        if let Some(ingest_path) = cli.ingest_path.clone() {
            unix_ingest::spawn_unix_ingest(
                ingest_path,
                cli.ingest_overwrite,
                cli.strict,
                spine_tx.clone(),
            )?;
        }

        // Optional stdin source.
        if matches!(cli.source, Source::Stdin) {
            spawn_stdin_source(spine_tx.clone(), cli.strict);
        }

        // Optional gRPC watch source.
        if !cli.watches.is_empty() {
            let cfg = grpc_health::GrpcWatchConfig {
                ttl_stale_s: cli.grpc_ttl_stale_s,
                ttl_dead_s: cli.grpc_ttl_dead_s,
            };

            let tls = grpc_health::GrpcTlsFiles {
                mode: cli.grpc_tls_mode,
                ca_pem: cli.grpc_ca.clone(),
                client_cert_pem: cli.grpc_cert.clone(),
                client_key_pem: cli.grpc_key.clone(),
                domain_name: cli.grpc_domain.clone(),
            };

            grpc_health::spawn_watchers(cli.watches.clone(), cfg, tls, spine_tx.clone());
        }

        // Optional systemd unit source.
        if !cli.units.is_empty() {
            let cfg = systemd::SystemdWatchConfig {
                ttl_stale_s: cli.systemd_ttl_stale_s,
                ttl_dead_s: cli.systemd_ttl_dead_s,
            };

            systemd::spawn_unit_watchers(cli.units.clone(), cfg, spine_tx.clone());
        }

        // Broadcast loop.
        for bytes in spine_rx {
            broadcast(&clients, &bytes);
        }

        Ok(())
    }
}
// :: ∎

// ▛▞// accept_loop :: hawkd.sock.accept
// ⫸ [sock.accept.push]
#[cfg(unix)]
fn accept_loop(listener: UnixListener, clients: Arc<Mutex<Vec<UnixStream>>>, banner: bool) {
    for incoming in listener.incoming() {
        match incoming {
            Ok(mut stream) => {
                if banner {
                    let _ = stream.write_all(b"# hawkd connected\n");
                }
                let _ = stream.flush();

                let mut lock = match clients.lock() {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                lock.push(stream);
            }
            Err(_) => continue,
        }
    }
}
// :: ∎

// ▛▞// spawn_stdin_source :: hawkd.stdin
// ⫸ [source.parse.emit]
fn spawn_stdin_source(tx: std::sync::mpsc::Sender<Vec<u8>>, strict: bool) {
    std::thread::spawn(move || {
        let stdin = io::stdin();
        let mut locked = stdin.lock();

        let mut line = String::new();
        loop {
            line.clear();
            let n = match locked.read_line(&mut line) {
                Ok(n) => n,
                Err(_) => break,
            };
            if n == 0 {
                break;
            }

            match HawkFrame::parse_tsv_line(&line) {
                Ok(Some(frame)) => {
                    let now = OffsetDateTime::now_utc();
                    let out = frame.to_tsv_line(now) + "\n";
                    let _ = tx.send(out.into_bytes());
                }
                Ok(None) => {}
                Err(e) => {
                    if strict {
                        let msg = format!("# hawkd strict parse error: {:?}\n", e);
                        let _ = tx.send(msg.into_bytes());
                        break;
                    }
                }
            }
        }
    });
}
// :: ∎

// ▛▞// broadcast :: hawkd.sock.broadcast
// ⫸ [sock.broadcast.dead]
#[cfg(unix)]
fn broadcast(clients: &Arc<Mutex<Vec<UnixStream>>>, bytes: &[u8]) {
    let mut lock = match clients.lock() {
        Ok(v) => v,
        Err(_) => return,
    };

    let mut i = 0usize;
    while i < lock.len() {
        let mut remove = false;
        if lock[i].write_all(bytes).is_err() {
            remove = true;
        } else {
            let _ = lock[i].flush();
        }

        if remove {
            lock.remove(i);
        } else {
            i += 1;
        }
    }
}
// :: ∎
