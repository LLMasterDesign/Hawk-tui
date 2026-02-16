// ▛▞// hawk io :: hawk.io
// @ctx ⫸ [ingest.stdin.error]
use std::io::{self, BufRead};

use hawk_core::{HawkFrame, HawkFrameParseError};

// ▛▞// ingest types :: hawk.io.types
// @ctx ⫸ [ingest.msg.error]
#[derive(Debug)]
pub enum IngestMsg {
    Frame(HawkFrame),
    ParseError(HawkFrameParseError),
    IoError(String),
}
// :: ∎

// ▛▞// stdin source :: hawk.io.stdin
// @ctx ⫸ [source.readline.parse]
pub fn spawn_stdin_reader(tx: std::sync::mpsc::Sender<IngestMsg>, strict: bool) {
    std::thread::spawn(move || {
        let stdin = io::stdin();
        let mut locked = stdin.lock();

        let mut line = String::new();
        loop {
            line.clear();
            match locked.read_line(&mut line) {
                Ok(0) => break,
                Ok(_) => match HawkFrame::parse_tsv_line(&line) {
                    Ok(Some(f)) => {
                        let _ = tx.send(IngestMsg::Frame(f));
                    }
                    Ok(None) => {}
                    Err(e) => {
                        let _ = tx.send(IngestMsg::ParseError(e.clone()));
                        if strict {
                            break;
                        }
                    }
                },
                Err(e) => {
                    let _ = tx.send(IngestMsg::IoError(e.to_string()));
                    break;
                }
            }
        }
    });
}
// :: ∎

// ▛▞// unix source :: hawk.io.unix
// ⫸ [source.connect.readlines]
pub fn spawn_unix_reader(
    tx: std::sync::mpsc::Sender<IngestMsg>,
    socket_path: &str,
    strict: bool,
) -> anyhow::Result<()> {
    #[cfg(not(unix))]
    {
        anyhow::bail!("unix socket source requires a unix platform (WSL, Linux, macOS)");
    }

    #[cfg(unix)]
    {
        use std::os::unix::net::UnixStream;

        let path = socket_path.to_string();
        std::thread::spawn(move || {
            let stream = match UnixStream::connect(&path) {
                Ok(s) => s,
                Err(e) => {
                    let _ = tx.send(IngestMsg::IoError(format!("connect {} failed: {}", path, e)));
                    return;
                }
            };

            let reader = std::io::BufReader::new(stream);
            for line in reader.lines() {
                match line {
                    Ok(line) => match HawkFrame::parse_tsv_line(&line) {
                        Ok(Some(f)) => {
                            let _ = tx.send(IngestMsg::Frame(f));
                        }
                        Ok(None) => {}
                        Err(e) => {
                            let _ = tx.send(IngestMsg::ParseError(e.clone()));
                            if strict {
                                break;
                            }
                        }
                    },
                    Err(e) => {
                        let _ = tx.send(IngestMsg::IoError(e.to_string()));
                        break;
                    }
                }
            }
        });

        Ok(())
    }
}
// :: ∎
