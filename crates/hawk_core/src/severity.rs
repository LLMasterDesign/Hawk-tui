// ▛▞// severity core :: hawk.core.severity
// @ctx ⫸ [level.parse.order]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Level {
    Ok,
    Info,
    Warn,
    Fail,
    Unknown,
}

impl Level {
    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "ok" => Level::Ok,
            "info" => Level::Info,
            "warn" | "warning" => Level::Warn,
            "fail" | "error" | "fatal" => Level::Fail,
            _ => Level::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Level::Ok => "ok",
            Level::Info => "info",
            Level::Warn => "warn",
            Level::Fail => "fail",
            Level::Unknown => "unknown",
        }
    }
}

/// Smaller is worse so sorting ascending puts failures first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct LevelRank(pub u8);

impl From<Level> for LevelRank {
    fn from(l: Level) -> Self {
        match l {
            Level::Fail => LevelRank(0),
            Level::Warn => LevelRank(1),
            Level::Info => LevelRank(2),
            Level::Ok => LevelRank(3),
            Level::Unknown => LevelRank(4),
        }
    }
}
// :: ∎
