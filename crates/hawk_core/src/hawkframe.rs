// ▛▞// hawkframe parser :: hawk.core.frame
// @ctx ⫸ [tsv.parse.compact]
use std::collections::BTreeMap;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::severity::Level;

#[derive(Debug, Clone)]
pub struct HawkFrame {
    pub ts: Option<OffsetDateTime>,
    pub kind: String,
    pub scope: String,
    pub id: String,
    pub level: Level,
    pub msg: String,
    /// kv bag: key=value;key=value (no spaces required, but supported)
    pub kv: BTreeMap<String, String>,
}

#[derive(Debug, Clone)]
pub enum HawkFrameParseError {
    Empty,
    TooFewColumns { found: usize },
    BadTimestamp { raw: String },
}

impl HawkFrame {
    /// TSV columns (7):
    /// ts, kind, scope, id, level, msg, kv
    ///
    /// Example:
    /// 2026-02-16T12:34:56Z  RECEIPT_EVENT  service  tape  ok  receipt written  trace_id=abc;status=ok
    pub fn parse_tsv_line(line: &str) -> Result<Option<HawkFrame>, HawkFrameParseError> {
        let line = line.trim_end_matches(['\n', '\r']);
        if line.trim().is_empty() {
            return Ok(None);
        }
        if line.trim_start().starts_with('#') {
            return Ok(None);
        }

        let cols: Vec<&str> = line.split('\t').collect();
        if cols.len() < 7 {
            return Err(HawkFrameParseError::TooFewColumns { found: cols.len() });
        }

        let raw_ts = cols[0].trim();
        let ts = if raw_ts.is_empty() {
            None
        } else {
            match OffsetDateTime::parse(raw_ts, &Rfc3339) {
                Ok(v) => Some(v),
                Err(_) => {
                    return Err(HawkFrameParseError::BadTimestamp {
                        raw: raw_ts.to_string(),
                    })
                }
            }
        };

        let kind = cols[1].trim().to_string();
        let scope = cols[2].trim().to_string();
        let id = cols[3].trim().to_string();
        let level = Level::parse(cols[4]);

        let msg = cols[5].trim().to_string();
        let kv_raw = cols[6].trim();

        let kv = parse_kv_bag(kv_raw);

        Ok(Some(HawkFrame {
            ts,
            kind,
            scope,
            id,
            level,
            msg,
            kv,
        }))
    }

    pub fn to_compact_line(&self) -> String {
        // For log tail display: keep it human and short.
        let ts = self
            .ts
            .map(|t| t.format(&Rfc3339).unwrap_or_default())
            .unwrap_or_default();
        format!(
            "{}\t{}\t{}\t{}\t{}\t{}",
            ts,
            self.kind,
            self.scope,
            self.id,
            self.level.as_str(),
            self.msg
        )
    }

    /// Emit a full TSV line suitable for piping to hawk or awk.
    /// If timestamp is missing, the provided `now` is stamped.
    pub fn to_tsv_line(&self, now: OffsetDateTime) -> String {
        let ts = self.ts.unwrap_or(now).format(&Rfc3339).unwrap_or_default();
        let kv = serialize_kv_bag(&self.kv);

        format!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}",
            ts,
            self.kind,
            self.scope,
            self.id,
            self.level.as_str(),
            self.msg,
            kv
        )
    }
}

fn parse_kv_bag(s: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    if s.trim().is_empty() {
        return out;
    }

    for part in s.split(';') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if let Some((k, v)) = part.split_once('=') {
            out.insert(k.trim().to_string(), v.trim().to_string());
        } else {
            // Support "bare flags" if present, treat as true.
            out.insert(part.to_string(), "true".to_string());
        }
    }
    out
}

fn serialize_kv_bag(kv: &BTreeMap<String, String>) -> String {
    if kv.is_empty() {
        return String::new();
    }
    let mut parts: Vec<String> = Vec::with_capacity(kv.len());
    for (k, v) in kv.iter() {
        if v == "true" {
            parts.push(k.clone());
        } else {
            parts.push(format!("{}={}", k, v));
        }
    }
    parts.join(";")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_line() {
        let line =
            "2026-02-16T12:34:56Z\tHEALTH\tservice\talpha\tok\talive\tpid=123;uptime_s=9";
        let f = HawkFrame::parse_tsv_line(line).unwrap().unwrap();
        assert_eq!(f.kind, "HEALTH");
        assert_eq!(f.scope, "service");
        assert_eq!(f.id, "alpha");
        assert_eq!(f.level.as_str(), "ok");
        assert_eq!(f.kv.get("pid").unwrap(), "123");
    }

    #[test]
    fn ignores_comments() {
        let line = "# comment";
        let f = HawkFrame::parse_tsv_line(line).unwrap();
        assert!(f.is_none());
    }

    #[test]
    fn emits_tsv_with_kv() {
        let line =
            "2026-02-16T12:34:56Z\tHEALTH\tservice\talpha\tok\talive\tpid=123;uptime_s=9";
        let f = HawkFrame::parse_tsv_line(line).unwrap().unwrap();
        let out = f.to_tsv_line(OffsetDateTime::now_utc());
        assert!(out.contains("\tHEALTH\tservice\talpha\tok\talive\t"));
        assert!(out.contains("pid=123"));
    }
}
// :: ∎
