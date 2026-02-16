// ▛▞// HAWKD::INGEST :: Unix producer socket
// @ctx ⫸ [unix.accept.emit]
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::mpsc::Sender;

use hawk_core::{HawkFrame, Level};
use time::OffsetDateTime;

#[cfg(unix)]
use std::os::unix::net::{UnixListener, UnixStream};

// :: ∎

// ▛▞// spawn ingest listener :: hawkd.ingest.spawn
// @ctx ⫸ [unix.accept.emit]
pub fn spawn_unix_ingest(
    ingest_path: PathBuf,
    overwrite: bool,
    strict: bool,
    spine_tx: Sender<Vec<u8>>,
) -> anyhow::Result<()> {
    #[cfg(not(unix))]
    {
        let _ = ingest_path;
        let _ = overwrite;
        let _ = strict;
        let _ = spine_tx;
        anyhow::bail!("unix ingest requires a unix platform (WSL, Linux, macOS)");
    }

    #[cfg(unix)]
    {
        if overwrite {
            let _ = std::fs::remove_file(&ingest_path);
        }

        let listener = UnixListener::bind(&ingest_path)?;

        std::thread::spawn(move || {
            for incoming in listener.incoming() {
                match incoming {
                    Ok(stream) => {
                        let tx = spine_tx.clone();
                        let path = ingest_path.clone();
                        std::thread::spawn(move || handle_ingest_client(stream, path, strict, tx));
                    }
                    Err(_) => {
                        // keep accepting
                        continue;
                    }
                }
            }
        });

        Ok(())
    }
}
// :: ∎

// ▛▞// handle_ingest_client :: hawkd.ingest.client
// @ctx ⫸ [readlines.parse.forward]
#[cfg(unix)]
fn handle_ingest_client(
    mut stream: UnixStream,
    ingest_path: PathBuf,
    strict: bool,
    spine_tx: Sender<Vec<u8>>,
) {
    let _ = stream.write_all(b"# hawkd ingest connected\n");
    let _ = stream.flush();

    let reader = std::io::BufReader::new(stream);

    for line in reader.lines() {
        match line {
            Ok(line) => match HawkFrame::parse_tsv_line(&line) {
                Ok(Some(frame)) => {
                    let now = OffsetDateTime::now_utc();
                    let out = frame.to_tsv_line(now) + "\n";
                    let _ = spine_tx.send(out.into_bytes());
                }
                Ok(None) => {}
                Err(e) => {
                    let now = OffsetDateTime::now_utc();
                    let err_frame = parse_error_frame(now, &ingest_path, &line, format!("{:?}", e));
                    let out = err_frame.to_tsv_line(now) + "\n";
                    let _ = spine_tx.send(out.into_bytes());

                    if strict {
                        break;
                    }
                }
            },
            Err(_) => break,
        }
    }
}
// :: ∎

// ▛▞// parse_error_frame :: hawkd.ingest.error
// ⫸ [emit.hawkd.parseerror]
fn parse_error_frame(now: OffsetDateTime, ingest_path: &PathBuf, raw: &str, err: String) -> HawkFrame {
    let mut kv = std::collections::BTreeMap::new();
    kv.insert(
        "ingest_path".to_string(),
        ingest_path.to_string_lossy().to_string(),
    );
    kv.insert("error".to_string(), err);

    // Avoid blasting full lines into kv; cap for safety.
    let mut clipped = raw.to_string();
    if clipped.len() > 240 {
        clipped.truncate(240);
        clipped.push_str("...");
    }
    kv.insert("raw".to_string(), clipped);

    HawkFrame {
        ts: Some(now),
        kind: "RECEIPT_EVENT".to_string(),
        scope: "hawkd".to_string(),
        id: "ingest".to_string(),
        level: Level::Warn,
        msg: "ingest parse error".to_string(),
        kv,
    }
}
// :: ∎
