// ▛▞// hawk pack doctor :: hawk.doctor
// @ctx ⫸ [doctor.security.scan]
// @ctx ⫸ [doctor.smoke.tsv]
// @ctx ⫸ [doctor.report.exit]
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use hawk_core::HawkFrame;

use crate::packs;

// :: ∎

// ▛▞// doctor types :: hawk.doctor.types
// ⫸ [security.mode.report]
#[derive(Debug, Clone, Copy)]
pub enum SecurityMode {
    Strict,
    Warn,
    Off,
}

#[derive(Debug, Clone)]
pub struct DoctorOptions {
    pub smoke: bool,
    pub security: SecurityMode,
}

#[derive(Debug, Clone)]
pub struct DoctorReport {
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

impl DoctorReport {
    pub fn new() -> Self {
        Self {
            errors: Vec::new(),
            warnings: Vec::new(),
        }
    }

    pub fn ok(&self) -> bool {
        self.errors.is_empty()
    }
}

#[derive(Debug, Clone, Copy)]
enum FindingSeverity {
    Error,
    Warning,
}

#[derive(Debug, Clone)]
struct SecurityFinding {
    severity: FindingSeverity,
    message: String,
}
// :: ∎

// ▛▞// run_pack_doctor :: hawk.doctor.run
// ⫸ [walk.scan.smoke]
pub fn run_pack_doctor(packs_dir: &Path, opts: DoctorOptions) -> DoctorReport {
    let mut rep = DoctorReport::new();

    if !packs_dir.exists() {
        rep.warnings
            .push(format!("packs dir missing: {:?}", packs_dir));
        return rep;
    }

    let mut entries = Vec::new();
    match fs::read_dir(packs_dir) {
        Ok(rd) => {
            for entry in rd.flatten() {
                let p = entry.path();
                if p.is_dir() {
                    entries.push(p);
                }
            }
        }
        Err(e) => {
            rep.errors
                .push(format!("cannot read packs dir {:?}: {}", packs_dir, e));
            return rep;
        }
    }
    entries.sort();

    let mut seen_thread_ids: BTreeMap<String, PathBuf> = BTreeMap::new();

    for pack_dir in entries {
        let manifest = pack_dir.join("pack.toml");
        if !manifest.exists() {
            continue;
        }

        let pack = match packs::parse_pack_manifest(&pack_dir, &manifest) {
            Ok(v) => v,
            Err(e) => {
                rep.errors
                    .push(format!("pack parse failed {:?}: {}", manifest, e));
                continue;
            }
        };

        if pack.threads.is_empty() {
            rep.warnings
                .push(format!("pack {:?} has zero threads", manifest));
        }

        for th in &pack.threads {
            if let Some(prev) = seen_thread_ids.get(&th.id) {
                rep.errors.push(format!(
                    "thread id collision '{}' between {:?} and {:?}",
                    th.id, prev, manifest
                ));
            } else {
                seen_thread_ids.insert(th.id.clone(), manifest.clone());
            }

            let script_path = pack.root_dir.join(&th.file);
            if !script_path.exists() {
                rep.errors.push(format!(
                    "thread '{}' missing file {:?}",
                    th.id, script_path
                ));
                continue;
            }

            if let Err(e) = check_header_and_terminator(&script_path) {
                rep.warnings
                    .push(format!("thread '{}' style: {}", th.id, e));
            }

            for w in scan_declared_arg_usage(&script_path, &th.args) {
                rep.warnings
                    .push(format!("thread '{}' schema: {}", th.id, w));
            }

            match security_scan_awk(&script_path, opts.security) {
                Ok(findings) => {
                    for f in findings {
                        match f.severity {
                            FindingSeverity::Error => {
                                rep.errors.push(format!("thread '{}' security: {}", th.id, f.message));
                            }
                            FindingSeverity::Warning => {
                                rep.warnings
                                    .push(format!("thread '{}' security: {}", th.id, f.message));
                            }
                        }
                    }
                }
                Err(e) => {
                    rep.errors
                        .push(format!("thread '{}' security scan failed: {}", th.id, e));
                }
            }

            if opts.smoke {
                let defaults = packs::default_tvars(&th.args);
                if let Err(e) = smoke_test_awk(&script_path, &defaults) {
                    rep.errors
                        .push(format!("thread '{}' smoke: {}", th.id, e));
                }
            }
        }
    }

    rep
}
// :: ∎

// ▛▞// style checks :: hawk.doctor.style
// ⫸ [header.terminator]
fn check_header_and_terminator(script_path: &Path) -> Result<(), String> {
    let raw = fs::read_to_string(script_path)
        .map_err(|e| format!("read {:?}: {}", script_path, e))?;

    let mut header_ok = false;
    for line in raw.lines().take(20) {
        if line.contains("▛▞//") {
            header_ok = true;
            break;
        }
    }

    if !header_ok {
        return Err("missing ▛▞// header in first 20 lines".to_string());
    }

    let mut last = "";
    for line in raw.lines() {
        let t = line.trim();
        if !t.is_empty() {
            last = t;
        }
    }

    if last != "# :: ∎" {
        return Err("missing terminator '# :: ∎' as last non-empty line".to_string());
    }

    Ok(())
}

fn scan_declared_arg_usage(script_path: &Path, args: &[packs::ArgSpec]) -> Vec<String> {
    if args.is_empty() {
        return Vec::new();
    }

    let raw = match fs::read_to_string(script_path) {
        Ok(v) => v,
        Err(e) => return vec![format!("read {:?}: {}", script_path, e)],
    };

    let mut out = Vec::new();
    for a in args {
        let needle = a.name.as_str();
        if !contains_word(&raw, needle) {
            out.push(format!("declared arg '{}' is never referenced", needle));
        }
    }

    out
}

fn contains_word(hay: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return false;
    }

    for line in hay.lines() {
        let t = line.trim();
        if t.starts_with('#') {
            continue;
        }

        let bytes = t.as_bytes();
        let n = needle.as_bytes();
        if n.len() > bytes.len() {
            continue;
        }

        let mut i = 0usize;
        while i + n.len() <= bytes.len() {
            if &bytes[i..i + n.len()] == n {
                let left_ok = i == 0 || !is_ident_char(bytes[i - 1] as char);
                let right_ok = i + n.len() == bytes.len()
                    || !is_ident_char(bytes[i + n.len()] as char);
                if left_ok && right_ok {
                    return true;
                }
            }
            i += 1;
        }
    }

    false
}

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}
// :: ∎

// ▛▞// security scan :: hawk.doctor.security
// ⫸ [deny.system.pipe.redirect]
fn security_scan_awk(script_path: &Path, mode: SecurityMode) -> Result<Vec<SecurityFinding>, String> {
    if matches!(mode, SecurityMode::Off) {
        return Ok(Vec::new());
    }

    let raw = fs::read_to_string(script_path)
        .map_err(|e| format!("read {:?}: {}", script_path, e))?;

    let mut findings: Vec<SecurityFinding> = Vec::new();
    let mut seen = BTreeSet::new();

    for line in raw.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }

        if t.contains("system(") {
            seen.insert("command execution via system() is not allowed".to_string());
        }

        if t.contains("| getline") || t.contains("|getline") {
            seen.insert("command pipe into getline is not allowed".to_string());
        }

        if (t.contains("print") || t.contains("printf")) && (t.contains("|\"") || t.contains("| \"")) {
            seen.insert("piping output to a command is not allowed".to_string());
        }

        if (t.contains("print") || t.contains("printf")) && (t.contains(">>") || t.contains('>')) {
            let allow_stderr = t.contains("/dev/stderr") || t.contains("/dev/fd/2");
            if !allow_stderr {
                seen.insert("file redirection is not allowed (only stderr debug is allowed)".to_string());
            }
        }

        if t.contains("getline <") || t.contains("getline<") {
            let severity = match mode {
                SecurityMode::Strict => FindingSeverity::Error,
                SecurityMode::Warn => FindingSeverity::Warning,
                SecurityMode::Off => FindingSeverity::Warning,
            };

            findings.push(SecurityFinding {
                severity,
                message: "getline file input detected, treat as high risk unless explicitly allowed".to_string(),
            });
        }
    }

    for msg in seen {
        findings.push(SecurityFinding {
            severity: FindingSeverity::Error,
            message: msg,
        });
    }

    Ok(findings)
}
// :: ∎

// ▛▞// smoke test :: hawk.doctor.smoke
// ⫸ [spawn.feed.validate]
fn smoke_test_awk(script_path: &Path, tvars: &BTreeMap<String, String>) -> Result<(), String> {
    let mut cmd = Command::new("awk");

    for (k, v) in tvars {
        cmd.arg("-v").arg(format!("{}={}", k, v));
    }

    cmd.arg("-f").arg(script_path);
    cmd.stdin(Stdio::piped());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::null());

    let mut child = cmd.spawn().map_err(|e| format!("spawn awk: {}", e))?;

    let mut stdin = child.stdin.take().ok_or_else(|| "awk stdin missing".to_string())?;
    let mut stdout = child.stdout.take().ok_or_else(|| "awk stdout missing".to_string())?;

    let sample = [
        "2026-02-16T00:00:00Z\tHEALTH\tsystemd\tspine.hawkd\tok\tactive\tunit=hawkd.service",
        "2026-02-16T00:00:01Z\tHEALTH\tgrpc\tproto.alpha\tfail\tNOT_SERVING\tendpoint=svc:443;service=;error=x",
        "2026-02-16T00:00:02Z\tRECEIPT_EVENT\thawkd\tingest\twarn\tingest parse error\terror=bad;raw=clip",
    ];

    for line in &sample {
        stdin
            .write_all(line.as_bytes())
            .map_err(|e| format!("write stdin: {}", e))?;
        stdin
            .write_all(b"\n")
            .map_err(|e| format!("write newline: {}", e))?;
    }
    drop(stdin);

    let mut out = String::new();
    stdout
        .read_to_string(&mut out)
        .map_err(|e| format!("read stdout: {}", e))?;

    let status = child.wait().map_err(|e| format!("wait awk: {}", e))?;
    if !status.success() {
        return Err("awk exited nonzero".to_string());
    }

    for line in out.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }

        match HawkFrame::parse_tsv_line(t) {
            Ok(Some(_)) => {}
            Ok(None) => {}
            Err(_) => {
                return Err(format!("invalid output line (not HawkFrame TSV): {}", t));
            }
        }
    }

    Ok(())
}
