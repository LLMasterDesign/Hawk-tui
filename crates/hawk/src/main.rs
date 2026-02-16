// ▛▞// hawk cli main :: hawk.main
// @ctx ⫸ [pack.transform.tui]
mod app;
mod awk;
mod doctor;
mod io;
mod packs;
mod ui;

use clap::{Parser, Subcommand, ValueEnum};

use std::collections::BTreeMap;
use std::path::PathBuf;

use app::App;
use hawk_core::HawkFrame;
use io::{spawn_stdin_reader, IngestMsg};

#[derive(Debug, Clone, Parser)]
#[command(name = "hawk", version, about = "Hawk TUI: event-driven health mirror for agents and services")]
struct Cli {
    #[command(subcommand)]
    cmd: Option<Command>,

    /// Source of HawkFrame TSV lines.
    #[arg(long, value_enum, default_value = "stdin")]
    source: Source,

    /// Unix socket path when source=unix.
    #[arg(long, default_value = "/tmp/hawk.sock")]
    socket_path: String,

    /// Treat bad lines as fatal. Default is to count and continue.
    #[arg(long, default_value_t = false)]
    strict: bool,

    /// Max events kept in the right-side tail.
    #[arg(long, default_value_t = 200)]
    tail_size: usize,

    /// Default stale TTL in seconds.
    #[arg(long, default_value_t = 10)]
    stale_s: i64,

    /// Default dead TTL in seconds.
    #[arg(long, default_value_t = 30)]
    dead_s: i64,

    /// Packs directory. Community adds packs here.
    #[arg(long, default_value = "./packs")]
    packs_dir: PathBuf,

    /// Transform selection:
    /// thread:<id> loads from packs
    /// file:<path> loads direct awk file
    #[arg(long, default_value = "none")]
    transform: String,

    /// Transform variables passed as -v key=value to awk.
    /// Repeatable: --tvar scope=grpc --tvar window_s=5
    #[arg(long = "tvar", value_parser = parse_kv)]
    tvars: Vec<(String, String)>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Source {
    Stdin,
    Unix,
}

#[derive(Debug, Subcommand, Clone)]
enum Command {
    /// Pack management commands.
    Pack {
        #[command(subcommand)]
        cmd: PackCommand,
    },

    /// Validate packs, security scan awk, optional smoke test.
    #[command(name = "pack-doctor")]
    PackDoctor {
        /// Enable smoke tests (runs awk threads on sample input).
        #[arg(long, default_value_t = true)]
        smoke: bool,

        /// Security mode: strict|warn|off
        #[arg(long, default_value = "strict")]
        security: String,
    },
}

#[derive(Debug, Subcommand, Clone)]
enum PackCommand {
    /// List all threads available in packs_dir.
    List,

    /// Show a thread detail and its schema.
    Show { thread_id: String },

    /// Validate packs, security scan awk, optional smoke test.
    Doctor {
        /// Enable smoke tests (runs awk threads on sample input).
        #[arg(long, default_value_t = true)]
        smoke: bool,

        /// Security mode: strict|warn|off
        #[arg(long, default_value = "strict")]
        security: String,
    },
}

fn parse_kv(s: &str) -> Result<(String, String), String> {
    let (k, v) = s.split_once('=').ok_or("expected key=value")?;
    let key = k.trim();
    let val = v.trim();
    if key.is_empty() {
        return Err("empty key".to_string());
    }
    Ok((key.to_string(), val.to_string()))
}

// :: ∎

// ▛▞// main :: hawk.main
// @ctx ⫸ [source.awk.bridge]
fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // Pack subcommands do not run TUI.
    if let Some(cmd) = cli.cmd.clone() {
        return run_pack_cmd(&cli, cmd);
    }

    let idx = packs::load_packs(&cli.packs_dir)?;

    let (tx_source, rx_source) = std::sync::mpsc::channel::<IngestMsg>();
    match cli.source {
        Source::Stdin => spawn_stdin_reader(tx_source, cli.strict),
        Source::Unix => {
            io::spawn_unix_reader(tx_source, &cli.socket_path, cli.strict)?;
        }
    }

    let (tx_ui, rx_ui) = std::sync::mpsc::channel::<IngestMsg>();
    let transform = cli.transform.trim().to_string();

    if transform == "none" {
        // No transform: pass source stream directly into UI.
        std::thread::spawn(move || {
            for msg in rx_source {
                let _ = tx_ui.send(msg);
            }
        });
    } else {
        let mut tvars: BTreeMap<String, String> = BTreeMap::new();
        for (k, v) in &cli.tvars {
            tvars.insert(k.clone(), v.clone());
        }

        let (mode, target) = parse_transform(&transform)?;
        let script_path = match mode.as_str() {
            "thread" => {
                let th = packs::resolve_thread(&idx, &target)
                    .ok_or_else(|| anyhow::anyhow!("thread not found: {}", target))?;

                let mut merged = packs::default_tvars(&th.args);
                for (k, v) in &tvars {
                    merged.insert(k.clone(), v.clone());
                }

                packs::validate_tvars(&th.args, &merged)
                    .map_err(anyhow::Error::msg)?;

                tvars = merged;
                th.script_path
            }
            "file" => PathBuf::from(target),
            _ => return Err(anyhow::anyhow!("unknown transform mode")),
        };

        let (tx_frames_raw, rx_frames_raw) = std::sync::mpsc::channel::<HawkFrame>();
        let (tx_frames_out, rx_frames_out) = std::sync::mpsc::channel::<HawkFrame>();
        let (tx_err, rx_err) = std::sync::mpsc::channel::<String>();

        let tx_ui_ingest = tx_ui.clone();
        std::thread::spawn(move || {
            for msg in rx_source {
                match msg {
                    IngestMsg::Frame(f) => {
                        let _ = tx_frames_raw.send(f);
                    }
                    other => {
                        let _ = tx_ui_ingest.send(other);
                    }
                }
            }
        });

        let runner = awk::AwkRunner::spawn(script_path, &tvars)?;
        runner.start_bridge(rx_frames_raw, tx_frames_out, tx_err);

        let tx_ui_frames = tx_ui.clone();
        std::thread::spawn(move || {
            for frame in rx_frames_out {
                let _ = tx_ui_frames.send(IngestMsg::Frame(frame));
            }
        });

        let tx_ui_err = tx_ui.clone();
        std::thread::spawn(move || {
            for err in rx_err {
                eprintln!("{}", err);
                let _ = tx_ui_err.send(IngestMsg::IoError(format!("awk: {}", err)));
            }
        });
    }

    let mut app = App::new(cli.tail_size, cli.stale_s, cli.dead_s);
    ui::run_tui(&mut app, rx_ui)?;

    Ok(())
}
// :: ∎

// ▛▞// pack commands :: hawk.pack.cmd
// @ctx ⫸ [pack.list.show]
fn run_pack_cmd(cli: &Cli, cmd: Command) -> anyhow::Result<()> {
    match cmd {
        Command::Pack { cmd } => {
            let idx = packs::load_packs(&cli.packs_dir)?;
            match cmd {
                PackCommand::List => {
                    let mut rows: Vec<_> = idx.threads.iter().collect();
                    rows.sort_by(|a, b| a.0.cmp(b.0));
                    for (id, th) in rows {
                        println!("{}\t{}\t{}\t{}", id, th.pack_id, th.kind, th.title);
                    }
                }
                PackCommand::Show { thread_id } => {
                    let th = packs::resolve_thread(&idx, &thread_id)
                        .ok_or_else(|| anyhow::anyhow!("thread not found: {}", thread_id))?;

                    println!("id: {}", th.thread_id);
                    println!("pack: {}", th.pack_id);
                    println!("kind: {}", th.kind);
                    println!("title: {}", th.title);
                    println!("desc: {}", th.description);
                    println!("script: {:?}", th.script_path);

                    if th.args.is_empty() {
                        println!("args: none");
                    } else {
                        println!("args:");
                        for a in &th.args {
                            let ty = match a.ty {
                                packs::ArgType::String => "string",
                                packs::ArgType::Int => "int",
                                packs::ArgType::Bool => "bool",
                            };
                            println!("  - {} ({}) default={} :: {}", a.name, ty, a.default, a.help);
                        }
                    }
                }
                PackCommand::Doctor { smoke, security } => {
                    run_doctor(cli, smoke, &security)?;
                }
            }
        }
        Command::PackDoctor { smoke, security } => {
            run_doctor(cli, smoke, &security)?;
        }
    }

    Ok(())
}
// :: ∎

// ▛▞// doctor entry :: hawk.pack.doctor
// ⫸ [security.smoke.exit]
fn run_doctor(cli: &Cli, smoke: bool, security: &str) -> anyhow::Result<()> {
    let sec_mode = match security {
        "strict" => doctor::SecurityMode::Strict,
        "warn" => doctor::SecurityMode::Warn,
        "off" => doctor::SecurityMode::Off,
        other => {
            return Err(anyhow::anyhow!(
                "unknown security mode '{}', expected strict|warn|off",
                other
            ));
        }
    };

    let opts = doctor::DoctorOptions {
        smoke,
        security: sec_mode,
    };

    let rep = doctor::run_pack_doctor(&cli.packs_dir, opts);

    for w in &rep.warnings {
        eprintln!("WARN\t{}", w);
    }
    for e in &rep.errors {
        eprintln!("FAIL\t{}", e);
    }

    if rep.ok() {
        println!("OK\tpack doctor passed");
        Ok(())
    } else {
        std::process::exit(2);
    }
}
// :: ∎

// ▛▞// parse_transform :: hawk.transform
// ⫸ [transform.parse.mode]
fn parse_transform(s: &str) -> Result<(String, String), anyhow::Error> {
    if let Some(rest) = s.strip_prefix("thread:") {
        let t = rest.trim().to_string();
        if t.is_empty() {
            return Err(anyhow::anyhow!("empty thread id"));
        }
        return Ok(("thread".to_string(), t));
    }

    if let Some(rest) = s.strip_prefix("file:") {
        let p = rest.trim().to_string();
        if p.is_empty() {
            return Err(anyhow::anyhow!("empty file path"));
        }
        return Ok(("file".to_string(), p));
    }

    Err(anyhow::anyhow!(
        "transform must be none, thread:<id>, or file:<path>"
    ))
}
// :: ∎
