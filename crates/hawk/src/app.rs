// ▛▞// hawk app state :: hawk.app
// @ctx ⫸ [entity.liveness.sort]
use std::collections::{BTreeMap, VecDeque};

use hawk_core::{HawkFrame, Level, LevelRank};
use time::OffsetDateTime;

use crate::io::IngestMsg;

#[derive(Debug, Clone)]
pub struct EntityState {
    pub scope: String,
    pub id: String,
    pub last_level: Level,
    pub last_msg: String,
    pub last_seen: OffsetDateTime,
    pub kind: String,
    pub kv: BTreeMap<String, String>,
}

#[derive(Debug)]
pub struct App {
    pub tail: VecDeque<String>,
    pub tail_size: usize,

    pub frames_seen: u64,
    pub parse_errors: u64,
    pub io_errors: u64,

    pub entities: BTreeMap<String, EntityState>, // key = scope:id

    pub stale_s: i64,
    pub dead_s: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Liveness {
    Active,
    Dream,
    Stale,
    Dead,
}

impl App {
    pub fn new(tail_size: usize, stale_s: i64, dead_s: i64) -> Self {
        Self {
            tail: VecDeque::with_capacity(tail_size),
            tail_size,
            frames_seen: 0,
            parse_errors: 0,
            io_errors: 0,
            entities: BTreeMap::new(),
            stale_s,
            dead_s,
        }
    }

    pub fn ingest(&mut self, msg: IngestMsg) {
        match msg {
            IngestMsg::Frame(f) => self.ingest_frame(f),
            IngestMsg::ParseError(_) => self.parse_errors += 1,
            IngestMsg::IoError(_) => self.io_errors += 1,
        }
    }

    fn ingest_frame(&mut self, f: HawkFrame) {
        self.frames_seen += 1;

        let compact = f.to_compact_line();

        let HawkFrame {
            ts,
            kind,
            scope,
            id,
            level,
            msg,
            kv,
        } = f;

        let now = OffsetDateTime::now_utc();
        let seen = ts.unwrap_or(now);

        let key = format!("{}:{}", scope, id);
        let st = EntityState {
            scope,
            id,
            last_level: level,
            last_msg: msg,
            last_seen: seen,
            kind,
            kv,
        };
        self.entities.insert(key, st);

        self.push_tail(compact);
    }

    fn push_tail(&mut self, line: String) {
        self.tail.push_front(line);
        while self.tail.len() > self.tail_size {
            self.tail.pop_back();
        }
    }

    pub fn compute_liveness(&self, last_seen: OffsetDateTime, now: OffsetDateTime) -> Liveness {
        self.compute_liveness_with_ttl(last_seen, now, self.stale_s, self.dead_s)
    }

    pub fn compute_liveness_with_ttl(
        &self,
        last_seen: OffsetDateTime,
        now: OffsetDateTime,
        stale_s: i64,
        dead_s: i64,
    ) -> Liveness {
        let age = now - last_seen;
        let age_s = age.whole_seconds();

        if age_s >= dead_s {
            return Liveness::Dead;
        }
        if age_s >= stale_s {
            return Liveness::Stale;
        }

        // Dream means quiet but within TTL.
        // Active means recent enough that it feels "live".
        // We define Active as within half the stale window.
        if age_s <= (stale_s / 2).max(1) {
            Liveness::Active
        } else {
            Liveness::Dream
        }
    }

    pub fn compute_entity_liveness(&self, st: &EntityState, now: OffsetDateTime) -> Liveness {
        let stale_s = parse_ttl_from_kv(&st.kv, "ttl_stale_s").unwrap_or(self.stale_s);
        let dead_s = parse_ttl_from_kv(&st.kv, "ttl_dead_s").unwrap_or(self.dead_s);
        self.compute_liveness_with_ttl(st.last_seen, now, stale_s, dead_s)
    }

    pub fn counts_by_state(&self) -> (u64, u64, u64, u64, u64, u64) {
        let now = OffsetDateTime::now_utc();
        let mut ok = 0u64;
        let mut warn = 0u64;
        let mut fail = 0u64;
        let mut stale = 0u64;
        let mut dead = 0u64;

        for st in self.entities.values() {
            match self.compute_entity_liveness(st, now) {
                Liveness::Stale => stale += 1,
                Liveness::Dead => dead += 1,
                _ => match st.last_level {
                    Level::Fail => fail += 1,
                    Level::Warn => warn += 1,
                    Level::Ok | Level::Info => ok += 1,
                    Level::Unknown => ok += 1,
                },
            }
        }

        let total = self.entities.len() as u64;
        (total, ok, warn, fail, stale, dead)
    }

    pub fn sorted_entities(&self) -> Vec<EntityState> {
        let now = OffsetDateTime::now_utc();
        let mut v: Vec<EntityState> = self.entities.values().cloned().collect();
        v.sort_by(|a, b| {
            let la = self.compute_entity_liveness(a, now);
            let lb = self.compute_entity_liveness(b, now);

            // Dead and Stale float to top, then severity, then recency.
            let rank_live = |l: Liveness| -> u8 {
                match l {
                    Liveness::Dead => 0,
                    Liveness::Stale => 1,
                    Liveness::Active => 2,
                    Liveness::Dream => 3,
                }
            };

            let ra = rank_live(la);
            let rb = rank_live(lb);
            ra.cmp(&rb)
                .then_with(|| LevelRank::from(a.last_level).cmp(&LevelRank::from(b.last_level)))
                .then_with(|| b.last_seen.cmp(&a.last_seen))
                .then_with(|| a.id.cmp(&b.id))
        });
        v
    }
}

fn parse_ttl_from_kv(kv: &BTreeMap<String, String>, key: &str) -> Option<i64> {
    let v = kv.get(key)?;
    let n = v.parse::<i64>().ok()?;
    if n > 0 {
        Some(n)
    } else {
        None
    }
}
// :: ∎
