// ▛▞// HAWKD::SYSTEMD :: Unit watch via D-Bus
// @ctx ⫸ [systemd.unit.watch]
use std::sync::mpsc::Sender;
use std::time::Duration;

use hawk_core::{HawkFrame, Level};
use time::OffsetDateTime;
use tokio_stream::StreamExt;
use zbus::zvariant::OwnedObjectPath;

// :: ∎

// ▛▞// UnitSpec :: hawkd.systemd.types
// @ctx ⫸ [unit.name.alias]
#[derive(Debug, Clone)]
pub struct UnitSpec {
    pub unit: String,
    pub id: String,
}

#[derive(Debug, Clone)]
pub struct SystemdWatchConfig {
    pub ttl_stale_s: i64,
    pub ttl_dead_s: i64,
}
// :: ∎

// ▛▞// parse_unit_spec :: hawkd.systemd.parse
// ⫸ [cli.unit.id]
pub fn parse_unit_spec(s: &str) -> Result<UnitSpec, String> {
    // format: unit,id
    // examples:
    //   hawkd.service
    //   hawkd.service,spine.hawkd
    let parts: Vec<&str> = s.split(',').collect();

    let unit = parts.first().map(|v| v.trim()).unwrap_or("");
    if unit.is_empty() {
        return Err("unit spec missing unit name".to_string());
    }

    let id = match parts.get(1).map(|v| v.trim()) {
        Some(v) if !v.is_empty() => v.to_string(),
        _ => unit.to_string(),
    };

    Ok(UnitSpec {
        unit: unit.to_string(),
        id,
    })
}
// :: ∎

// ▛▞// spawn watchers :: hawkd.systemd.spawn
// @ctx ⫸ [tokio.spawn.unit]
pub fn spawn_unit_watchers(units: Vec<UnitSpec>, cfg: SystemdWatchConfig, tx: Sender<Vec<u8>>) {
    if units.is_empty() {
        return;
    }

    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");

        rt.block_on(async move {
            for spec in units {
                let tx2 = tx.clone();
                let cfg2 = cfg.clone();
                tokio::spawn(async move {
                    watch_one_unit(spec, cfg2, tx2).await;
                });
            }

            loop {
                tokio::time::sleep(Duration::from_secs(3600)).await;
            }
        });
    });
}
// :: ∎

// ▛▞// watch_one_unit :: hawkd.systemd.watch
// ⫸ [systembus.watch.backoff]
async fn watch_one_unit(spec: UnitSpec, cfg: SystemdWatchConfig, tx: Sender<Vec<u8>>) {
    let mut backoff_ms: u64 = 250;
    let max_backoff_ms: u64 = 15_000;

    loop {
        match watch_one_unit_once(&spec, &cfg, &tx).await {
            Ok(_) => {
                backoff_ms = 250;
                tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
            }
            Err(err) => {
                emit_error_frame(&spec, &cfg, &tx, "systemd watch failed", &err);
                tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
                backoff_ms = (backoff_ms * 2).min(max_backoff_ms);
            }
        }
    }
}
// :: ∎

// ▛▞// watch_one_unit_once :: hawkd.systemd.once
// ⫸ [connect.unit.properties]
async fn watch_one_unit_once(
    spec: &UnitSpec,
    cfg: &SystemdWatchConfig,
    tx: &Sender<Vec<u8>>,
) -> Result<(), String> {
    let conn = zbus::Connection::system()
        .await
        .map_err(|e| format!("connect system bus: {}", e))?;

    let manager = ManagerProxy::new(&conn)
        .await
        .map_err(|e| format!("manager proxy: {}", e))?;

    let unit_path = manager
        .get_unit(&spec.unit)
        .await
        .map_err(|e| format!("GetUnit {}: {}", spec.unit, e))?;

    let unit = UnitProxy::builder(&conn)
        .path(unit_path.clone())
        .map_err(|e| format!("unit proxy builder: {}", e))?
        .build()
        .await
        .map_err(|e| format!("unit proxy build: {}", e))?;

    let props = zbus::fdo::PropertiesProxy::builder(&conn)
        .destination("org.freedesktop.systemd1")
        .map_err(|e| format!("properties destination: {}", e))?
        .path(unit_path.clone())
        .map_err(|e| format!("properties path: {}", e))?
        .build()
        .await
        .map_err(|e| format!("properties proxy: {}", e))?;

    emit_snapshot_frame(spec, cfg, tx, &unit).await?;

    let mut stream = props
        .receive_properties_changed()
        .await
        .map_err(|e| format!("receive PropertiesChanged: {}", e))?;

    while let Some(_sig) = stream.next().await {
        emit_snapshot_frame(spec, cfg, tx, &unit).await?;
    }

    Err("properties stream ended".to_string())
}
// :: ∎

// ▛▞// emit_snapshot_frame :: hawkd.systemd.snapshot
// ⫸ [state.level.emit]
async fn emit_snapshot_frame(
    spec: &UnitSpec,
    cfg: &SystemdWatchConfig,
    tx: &Sender<Vec<u8>>,
    unit: &UnitProxy<'_>,
) -> Result<(), String> {
    let now = OffsetDateTime::now_utc();

    let active = unit
        .active_state()
        .await
        .map_err(|e| format!("ActiveState: {}", e))?;
    let sub = unit
        .sub_state()
        .await
        .map_err(|e| format!("SubState: {}", e))?;
    let load = unit
        .load_state()
        .await
        .map_err(|e| format!("LoadState: {}", e))?;
    let desc = unit.description().await.unwrap_or_else(|_| String::new());

    let level = map_systemd_level(&active, &sub, &load);

    let mut kv = std::collections::BTreeMap::new();
    kv.insert("unit".to_string(), spec.unit.clone());
    kv.insert("active".to_string(), active.clone());
    kv.insert("sub".to_string(), sub.clone());
    kv.insert("load".to_string(), load.clone());
    if !desc.is_empty() {
        kv.insert("desc".to_string(), desc);
    }
    kv.insert("ttl_stale_s".to_string(), cfg.ttl_stale_s.to_string());
    kv.insert("ttl_dead_s".to_string(), cfg.ttl_dead_s.to_string());

    let frame = HawkFrame {
        ts: Some(now),
        kind: "HEALTH".to_string(),
        scope: "systemd".to_string(),
        id: spec.id.clone(),
        level,
        msg: format!("{}:{}", active, sub),
        kv,
    };

    let out = frame.to_tsv_line(now) + "\n";
    let _ = tx.send(out.into_bytes());
    Ok(())
}
// :: ∎

// ▛▞// map_systemd_level :: hawkd.systemd.map
// ⫸ [active.state.level]
fn map_systemd_level(active: &str, sub: &str, load: &str) -> Level {
    let a = active.to_ascii_lowercase();
    let s = sub.to_ascii_lowercase();
    let l = load.to_ascii_lowercase();

    if l == "not-found" {
        return Level::Fail;
    }

    if a == "failed" || s == "failed" {
        return Level::Fail;
    }

    if a == "active" {
        return Level::Ok;
    }

    if a == "activating" || a == "reloading" {
        return Level::Info;
    }

    if a == "deactivating" || a == "inactive" {
        return Level::Warn;
    }

    Level::Unknown
}
// :: ∎

// ▛▞// emit_error_frame :: hawkd.systemd.error
// ⫸ [emit.fail.error]
fn emit_error_frame(
    spec: &UnitSpec,
    cfg: &SystemdWatchConfig,
    tx: &Sender<Vec<u8>>,
    msg: &str,
    err: &str,
) {
    let now = OffsetDateTime::now_utc();

    let mut kv = std::collections::BTreeMap::new();
    kv.insert("unit".to_string(), spec.unit.clone());
    kv.insert("error".to_string(), err.to_string());
    kv.insert("ttl_stale_s".to_string(), cfg.ttl_stale_s.to_string());
    kv.insert("ttl_dead_s".to_string(), cfg.ttl_dead_s.to_string());

    let frame = HawkFrame {
        ts: Some(now),
        kind: "HEALTH".to_string(),
        scope: "systemd".to_string(),
        id: spec.id.clone(),
        level: Level::Fail,
        msg: msg.to_string(),
        kv,
    };

    let out = frame.to_tsv_line(now) + "\n";
    let _ = tx.send(out.into_bytes());
}
// :: ∎

// ▛▞// zbus proxies :: hawkd.systemd.proxies
// ⫸ [manager.unit.properties]
#[zbus::proxy(
    interface = "org.freedesktop.systemd1.Manager",
    default_service = "org.freedesktop.systemd1",
    default_path = "/org/freedesktop/systemd1"
)]
trait Manager {
    fn get_unit(&self, name: &str) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(
    interface = "org.freedesktop.systemd1.Unit",
    default_service = "org.freedesktop.systemd1"
)]
trait Unit {
    #[zbus(property)]
    fn active_state(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn sub_state(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn load_state(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn description(&self) -> zbus::Result<String>;
}
// :: ∎
