// ▛▞// hawk awk runner :: hawk.awk
// @ctx ⫸ [awk.stream.bridge]
use std::collections::BTreeMap;
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::mpsc::{Receiver, Sender};

use hawk_core::HawkFrame;
use time::OffsetDateTime;

// :: ∎

// ▛▞// AwkRunner :: hawk.awk.runner
// @ctx ⫸ [awk.process.spawn]
pub struct AwkRunner {
    child: Child,
    stdin: ChildStdin,
    stdout: ChildStdout,
}

impl AwkRunner {
    pub fn spawn(script_path: PathBuf, tvars: &BTreeMap<String, String>) -> anyhow::Result<Self> {
        if !script_path.exists() {
            anyhow::bail!("awk script not found: {:?}", script_path);
        }

        let mut cmd = Command::new("awk");

        // Pass transform variables as -v key=value args.
        for (k, v) in tvars {
            cmd.arg("-v").arg(format!("{}={}", k, v));
        }

        cmd.arg("-f").arg(script_path);
        cmd.stdin(Stdio::piped());
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::inherit());

        let mut child = cmd.spawn()?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow::anyhow!("awk stdin missing"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow::anyhow!("awk stdout missing"))?;

        Ok(Self {
            child,
            stdin,
            stdout,
        })
    }

    pub fn start_bridge(
        self,
        in_rx: Receiver<HawkFrame>,
        out_tx: Sender<HawkFrame>,
        err_tx: Sender<String>,
    ) {
        let mut stdin = self.stdin;
        let stdout = self.stdout;
        let mut child = self.child;

        let err_tx_writer = err_tx.clone();
        std::thread::spawn(move || {
            for frame in in_rx {
                let now = OffsetDateTime::now_utc();
                let line = frame.to_tsv_line(now);
                if stdin.write_all(line.as_bytes()).is_err() {
                    let _ = err_tx_writer.send("awk stdin write failed".to_string());
                    break;
                }
                if stdin.write_all(b"\n").is_err() {
                    let _ = err_tx_writer.send("awk stdin newline failed".to_string());
                    break;
                }
                if stdin.flush().is_err() {
                    let _ = err_tx_writer.send("awk stdin flush failed".to_string());
                    break;
                }
            }
        });

        let err_tx_reader = err_tx.clone();
        std::thread::spawn(move || {
            let reader = std::io::BufReader::new(stdout);
            for line in reader.lines() {
                match line {
                    Ok(line) => match HawkFrame::parse_tsv_line(&line) {
                        Ok(Some(frame)) => {
                            let _ = out_tx.send(frame);
                        }
                        Ok(None) => {}
                        Err(_) => {
                            let _ = err_tx_reader.send("awk emitted invalid TSV line".to_string());
                        }
                    },
                    Err(_) => {
                        let _ = err_tx_reader.send("awk stdout read failed".to_string());
                        break;
                    }
                }
            }
        });

        std::thread::spawn(move || match child.wait() {
            Ok(status) => {
                if !status.success() {
                    let _ = err_tx.send(format!("awk exited with status {}", status));
                }
            }
            Err(e) => {
                let _ = err_tx.send(format!("awk wait failed: {}", e));
            }
        });
    }
}
// :: ∎
