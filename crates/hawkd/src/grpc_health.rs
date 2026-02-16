// ▛▞// HAWKD::GRPC_HEALTH :: Watch + TLS + mTLS
// @ctx ⫸ [grpc.watch.mtls]
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::time::Duration;

use hawk_core::{HawkFrame, Level};
use time::OffsetDateTime;

use tokio_stream::StreamExt;

use tonic::transport::{Certificate, Channel, ClientTlsConfig, Endpoint, Identity};
use tonic_health::pb::{
    health_check_response::ServingStatus,
    health_client::HealthClient,
    HealthCheckRequest,
};

// :: ∎

// ▛▞// types :: hawkd.grpc.types
// @ctx ⫸ [watchspec.tlsmode.tlsfiles]
#[derive(Debug, Clone)]
pub struct WatchSpec {
    pub endpoint: String, // host:port or http(s)://host:port
    pub service: String,  // "" means whole server
    pub id: String,       // entity id shown in Hawk TUI
}

#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub enum GrpcTlsMode {
    Off,
    Tls,
    Mtls,
}

#[derive(Debug, Clone)]
pub struct GrpcTlsFiles {
    pub mode: GrpcTlsMode,
    pub ca_pem: Option<PathBuf>,
    pub client_cert_pem: Option<PathBuf>,
    pub client_key_pem: Option<PathBuf>,
    pub domain_name: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GrpcWatchConfig {
    pub ttl_stale_s: i64,
    pub ttl_dead_s: i64,
}
// :: ∎

// ▛▞// parse_watch_spec :: hawkd.grpc.parse
// @ctx ⫸ [cli.watch.id]
pub fn parse_watch_spec(s: &str) -> Result<WatchSpec, String> {
    // format: endpoint,service,id
    // examples:
    //   127.0.0.1:50051
    //   https://service:8080,,proto.alpha
    //   service:8443,My.Service,svc.my
    let parts: Vec<&str> = s.split(',').collect();

    let endpoint = parts.get(0).map(|v| v.trim()).unwrap_or("");
    if endpoint.is_empty() {
        return Err("watch spec missing endpoint".to_string());
    }

    let service = parts.get(1).map(|v| v.trim()).unwrap_or("").to_string();

    let id = match parts.get(2).map(|v| v.trim()) {
        Some(v) if !v.is_empty() => v.to_string(),
        _ => {
            let mut base = endpoint.replace("http://", "").replace("https://", "");
            base = base.replace('/', "_").replace(':', "_");
            if service.is_empty() {
                format!("grpc.{}", base)
            } else {
                let svc = service.replace('/', "_").replace(':', "_");
                format!("grpc.{}.{}", base, svc)
            }
        }
    };

    Ok(WatchSpec {
        endpoint: endpoint.to_string(),
        service,
        id,
    })
}
// :: ∎

// ▛▞// spawn watchers :: hawkd.grpc.spawn
// ⫸ [tokio.spawn.watchspec]
pub fn spawn_watchers(
    specs: Vec<WatchSpec>,
    cfg: GrpcWatchConfig,
    tls: GrpcTlsFiles,
    tx: Sender<Vec<u8>>,
) {
    if specs.is_empty() {
        return;
    }

    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");

        rt.block_on(async move {
            for spec in specs {
                let tx2 = tx.clone();
                let cfg2 = cfg.clone();
                let tls2 = tls.clone();
                tokio::spawn(async move {
                    watch_one(spec, cfg2, tls2, tx2).await;
                });
            }

            loop {
                tokio::time::sleep(Duration::from_secs(3600)).await;
            }
        });
    });
}
// :: ∎

// ▛▞// watch_one :: hawkd.grpc.watch
// ⫸ [grpc.watch.backoff]
async fn watch_one(spec: WatchSpec, cfg: GrpcWatchConfig, tls: GrpcTlsFiles, tx: Sender<Vec<u8>>) {
    let mut backoff_ms: u64 = 250;
    let max_backoff_ms: u64 = 15_000;

    loop {
        let channel = match connect_channel(&spec, &tls).await {
            Ok(ch) => ch,
            Err(err) => {
                emit_error_frame(&spec, &cfg, &tx, "connect failed", &err);
                tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
                backoff_ms = (backoff_ms * 2).min(max_backoff_ms);
                continue;
            }
        };

        backoff_ms = 250;

        let mut client = HealthClient::new(channel);

        let req = tonic::Request::new(HealthCheckRequest {
            service: spec.service.clone(),
        });

        let stream = match client.watch(req).await {
            Ok(resp) => resp.into_inner(),
            Err(status) => {
                emit_error_frame(&spec, &cfg, &tx, "watch failed", &status.to_string());
                tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
                backoff_ms = (backoff_ms * 2).min(max_backoff_ms);
                continue;
            }
        };

        tokio::pin!(stream);

        while let Some(item) = stream.next().await {
            match item {
                Ok(msg) => {
                    let status =
                        ServingStatus::try_from(msg.status).unwrap_or(ServingStatus::Unknown);
                    emit_status_frame(&spec, &cfg, &tx, status);
                }
                Err(e) => {
                    emit_error_frame(&spec, &cfg, &tx, "stream error", &e.to_string());
                    break;
                }
            }
        }

        tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
        backoff_ms = (backoff_ms * 2).min(max_backoff_ms);
    }
}
// :: ∎

// ▛▞// connect_channel :: hawkd.grpc.connect
// ⫸ [endpoint.normalize.tlsconfig]
async fn connect_channel(spec: &WatchSpec, tls: &GrpcTlsFiles) -> Result<Channel, String> {
    let uri = normalize_endpoint_uri(&spec.endpoint, tls.mode);

    let mut ep = Endpoint::from_shared(uri.clone())
        .map_err(|e| format!("bad endpoint uri {}: {}", uri, e))?
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(15));

    match tls.mode {
        GrpcTlsMode::Off => {}
        GrpcTlsMode::Tls | GrpcTlsMode::Mtls => {
            let cfg = build_tls_config(&uri, tls)?;
            ep = ep.tls_config(cfg).map_err(|e| format!("tls_config: {}", e))?;
        }
    }

    ep.connect().await.map_err(|e| format!("connect: {}", e))
}
// :: ∎

// ▛▞// normalize_endpoint_uri :: hawkd.grpc.uri
// ⫸ [scheme.http.mode]
fn normalize_endpoint_uri(raw: &str, mode: GrpcTlsMode) -> String {
    let s = raw.trim();
    if s.starts_with("http://") || s.starts_with("https://") {
        return s.to_string();
    }

    match mode {
        GrpcTlsMode::Off => format!("http://{}", s),
        GrpcTlsMode::Tls | GrpcTlsMode::Mtls => format!("https://{}", s),
    }
}
// :: ∎

// ▛▞// build_tls_config :: hawkd.grpc.tls
// ⫸ [ca.required.domainname]
fn build_tls_config(uri: &str, tls: &GrpcTlsFiles) -> Result<ClientTlsConfig, String> {
    let ca_path = tls
        .ca_pem
        .clone()
        .ok_or_else(|| "tls requires --grpc-ca <path>".to_string())?;

    let ca_pem =
        std::fs::read(&ca_path).map_err(|e| format!("read ca pem {:?}: {}", ca_path, e))?;
    let ca = Certificate::from_pem(ca_pem);

    let domain = if let Some(d) = tls.domain_name.clone() {
        d
    } else {
        derive_host_from_uri(uri)
            .ok_or_else(|| "unable to derive domain name, pass --grpc-domain".to_string())?
    };

    let mut cfg = ClientTlsConfig::new().ca_certificate(ca).domain_name(domain);

    if matches!(tls.mode, GrpcTlsMode::Mtls) {
        let cert_path = tls
            .client_cert_pem
            .clone()
            .ok_or_else(|| "mtls requires --grpc-cert <path>".to_string())?;
        let key_path = tls
            .client_key_pem
            .clone()
            .ok_or_else(|| "mtls requires --grpc-key <path>".to_string())?;

        let cert = std::fs::read(&cert_path)
            .map_err(|e| format!("read client cert {:?}: {}", cert_path, e))?;
        let key = std::fs::read(&key_path)
            .map_err(|e| format!("read client key {:?}: {}", key_path, e))?;

        let id = Identity::from_pem(cert, key);
        cfg = cfg.identity(id);
    }

    Ok(cfg)
}
// :: ∎

// ▛▞// derive_host_from_uri :: hawkd.grpc.host
// ⫸ [host.extract.verify]
fn derive_host_from_uri(uri: &str) -> Option<String> {
    let s = uri.split("://").nth(1)?;
    let host_port = s.split('/').next().unwrap_or(s);
    let host = host_port.split(':').next().unwrap_or(host_port);
    if host.is_empty() {
        None
    } else {
        Some(host.to_string())
    }
}
// :: ∎

// ▛▞// emit_status_frame :: hawkd.grpc.emit.status
// ⫸ [frame.health.map]
fn emit_status_frame(
    spec: &WatchSpec,
    cfg: &GrpcWatchConfig,
    tx: &Sender<Vec<u8>>,
    st: ServingStatus,
) {
    let (level, msg) = match st {
        ServingStatus::Serving => (Level::Ok, "SERVING"),
        ServingStatus::NotServing => (Level::Fail, "NOT_SERVING"),
        ServingStatus::ServiceUnknown => (Level::Warn, "SERVICE_UNKNOWN"),
        ServingStatus::Unknown => (Level::Unknown, "UNKNOWN"),
    };

    let mut kv = std::collections::BTreeMap::new();
    kv.insert("endpoint".to_string(), spec.endpoint.clone());
    kv.insert("service".to_string(), spec.service.clone());
    kv.insert("grpc_status".to_string(), format!("{:?}", st));
    kv.insert("ttl_stale_s".to_string(), cfg.ttl_stale_s.to_string());
    kv.insert("ttl_dead_s".to_string(), cfg.ttl_dead_s.to_string());

    let frame = HawkFrame {
        ts: Some(OffsetDateTime::now_utc()),
        kind: "HEALTH".to_string(),
        scope: "grpc".to_string(),
        id: spec.id.clone(),
        level,
        msg: msg.to_string(),
        kv,
    };

    let out = frame.to_tsv_line(OffsetDateTime::now_utc()) + "\n";
    let _ = tx.send(out.into_bytes());
}
// :: ∎

// ▛▞// emit_error_frame :: hawkd.grpc.emit.error
// ⫸ [frame.health.error]
fn emit_error_frame(
    spec: &WatchSpec,
    cfg: &GrpcWatchConfig,
    tx: &Sender<Vec<u8>>,
    msg: &str,
    err: &str,
) {
    let mut kv = std::collections::BTreeMap::new();
    kv.insert("endpoint".to_string(), spec.endpoint.clone());
    kv.insert("service".to_string(), spec.service.clone());
    kv.insert("error".to_string(), err.to_string());
    kv.insert("ttl_stale_s".to_string(), cfg.ttl_stale_s.to_string());
    kv.insert("ttl_dead_s".to_string(), cfg.ttl_dead_s.to_string());

    let frame = HawkFrame {
        ts: Some(OffsetDateTime::now_utc()),
        kind: "HEALTH".to_string(),
        scope: "grpc".to_string(),
        id: spec.id.clone(),
        level: Level::Fail,
        msg: msg.to_string(),
        kv,
    };

    let out = frame.to_tsv_line(OffsetDateTime::now_utc()) + "\n";
    let _ = tx.send(out.into_bytes());
}
// :: ∎
