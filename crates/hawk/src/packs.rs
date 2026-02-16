// ▛▞// hawk packs loader :: hawk.packs
// @ctx ⫸ [pack.load.validate]
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Component, Path, PathBuf};

use anyhow::Context;
use serde::Deserialize;

// :: ∎

// ▛▞// public model :: hawk.packs.model
// @ctx ⫸ [thread.schema.args]
#[derive(Debug, Clone)]
pub struct PackIndex {
    pub packs: Vec<Pack>,
    pub threads: HashMap<String, ThreadResolved>,
}

#[derive(Debug, Clone)]
pub struct Pack {
    pub id: String,
    pub name: String,
    pub version: String,
    pub author: String,
    pub description: String,
    pub root_dir: PathBuf,
    pub threads: Vec<Thread>,
}

#[derive(Debug, Clone)]
pub struct Thread {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub file: String,
    pub description: String,
    pub args: Vec<ArgSpec>,
}

#[derive(Debug, Clone)]
pub struct ArgSpec {
    pub name: String,
    pub ty: ArgType,
    pub default: String,
    pub help: String,
}

#[derive(Debug, Clone, Copy)]
pub enum ArgType {
    String,
    Int,
    Bool,
}

#[derive(Debug, Clone)]
pub struct ThreadResolved {
    pub pack_id: String,
    pub thread_id: String,
    pub title: String,
    pub kind: String,
    pub description: String,
    pub script_path: PathBuf,
    pub args: Vec<ArgSpec>,
}
// :: ∎

// ▛▞// manifest types :: hawk.packs.manifest
// @ctx ⫸ [path.safety.rules]
#[derive(Debug, Deserialize)]
struct Manifest {
    pack: ManifestPack,
    #[serde(default)]
    thread: Vec<ManifestThread>,
}

#[derive(Debug, Deserialize)]
struct ManifestPack {
    id: String,
    name: String,
    version: String,
    author: String,
    #[serde(default)]
    description: String,
}

#[derive(Debug, Deserialize)]
struct ManifestThread {
    id: String,
    title: String,
    kind: String,
    file: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    arg: Vec<ManifestArg>,
}

#[derive(Debug, Deserialize)]
struct ManifestArg {
    name: String,
    #[serde(rename = "type")]
    ty: String,
    #[serde(default)]
    default: Option<toml::Value>,
    #[serde(default)]
    help: String,
}
// :: ∎

// ▛▞// load_packs :: hawk.packs.load
// ⫸ [discover.parse.index]
pub fn load_packs(packs_dir: &Path) -> anyhow::Result<PackIndex> {
    let mut packs: Vec<Pack> = Vec::new();
    let mut threads: HashMap<String, ThreadResolved> = HashMap::new();

    if !packs_dir.exists() {
        return Ok(PackIndex { packs, threads });
    }

    let mut dirs = Vec::new();
    for entry in fs::read_dir(packs_dir).with_context(|| format!("read packs dir {:?}", packs_dir))? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            dirs.push(path);
        }
    }
    dirs.sort();

    for dir in dirs {
        let manifest_path = dir.join("pack.toml");
        if !manifest_path.exists() {
            continue;
        }

        let pack = parse_pack_manifest(&dir, &manifest_path)
            .with_context(|| format!("parse pack {:?}", manifest_path))?;

        for th in &pack.threads {
            let resolved = ThreadResolved {
                pack_id: pack.id.clone(),
                thread_id: th.id.clone(),
                title: th.title.clone(),
                kind: th.kind.clone(),
                description: th.description.clone(),
                script_path: pack.root_dir.join(&th.file),
                args: th.args.clone(),
            };

            if threads.contains_key(&th.id) {
                anyhow::bail!("thread id collision: {}", th.id);
            }

            threads.insert(th.id.clone(), resolved);
        }

        packs.push(pack);
    }

    Ok(PackIndex { packs, threads })
}
// :: ∎

// ▛▞// resolve_thread :: hawk.packs.resolve
// ⫸ [thread.id.lookup]
pub fn resolve_thread(idx: &PackIndex, thread_id: &str) -> Option<ThreadResolved> {
    idx.threads.get(thread_id).cloned()
}
// :: ∎

// ▛▞// validate_tvars :: hawk.packs.tvars
// ⫸ [schema.validate.value]
pub fn validate_tvars(args: &[ArgSpec], tvars: &BTreeMap<String, String>) -> Result<(), String> {
    let mut allowed: HashMap<String, ArgSpec> = HashMap::new();
    for a in args {
        allowed.insert(a.name.clone(), a.clone());
    }

    for (k, v) in tvars {
        let spec = allowed.get(k).ok_or_else(|| format!("unknown tvar: {}", k))?;
        match spec.ty {
            ArgType::String => {}
            ArgType::Int => {
                v.parse::<i64>()
                    .map_err(|_| format!("tvar {} expects int, got {}", k, v))?;
            }
            ArgType::Bool => {
                let vv = v.to_ascii_lowercase();
                if vv != "true" && vv != "false" && vv != "1" && vv != "0" {
                    return Err(format!("tvar {} expects bool, got {}", k, v));
                }
            }
        }
    }

    Ok(())
}

pub fn default_tvars(args: &[ArgSpec]) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for a in args {
        out.insert(a.name.clone(), a.default.clone());
    }
    out
}
// :: ∎

// ▛▞// parse manifest :: hawk.packs.parse
// ⫸ [toml.path.safe]
pub fn parse_pack_manifest(pack_dir: &Path, manifest_path: &Path) -> anyhow::Result<Pack> {
    let raw = fs::read_to_string(manifest_path)
        .with_context(|| format!("read manifest {:?}", manifest_path))?;

    let man: Manifest = toml::from_str(&raw)
        .with_context(|| "toml deserialize")?;

    let mut threads: Vec<Thread> = Vec::new();

    for t in man.thread {
        ensure_safe_rel_path(&t.file)
            .map_err(|e| anyhow::anyhow!("thread {} file path unsafe: {}", t.id, e))?;

        if t.id.trim().is_empty() {
            anyhow::bail!("thread id cannot be empty");
        }

        if t.kind.trim().is_empty() {
            anyhow::bail!("thread {} kind cannot be empty", t.id);
        }

        let script_path = pack_dir.join(&t.file);
        if !script_path.exists() {
            anyhow::bail!("thread {} references missing file {:?}", t.id, script_path);
        }

        let mut args = Vec::new();
        for a in t.arg {
            let ty = parse_arg_type(&a.ty)
                .map_err(|e| anyhow::anyhow!("thread {} arg {}: {}", t.id, a.name, e))?;

            let spec = ArgSpec {
                name: a.name,
                ty,
                default: toml_value_to_string(a.default),
                help: a.help,
            };

            validate_arg_default(&spec)
                .map_err(|e| anyhow::anyhow!("thread {} arg {}: {}", t.id, spec.name, e))?;

            args.push(spec);
        }

        threads.push(Thread {
            id: t.id,
            title: t.title,
            kind: t.kind,
            file: t.file,
            description: t.description,
            args,
        });
    }

    Ok(Pack {
        id: man.pack.id,
        name: man.pack.name,
        version: man.pack.version,
        author: man.pack.author,
        description: man.pack.description,
        root_dir: pack_dir.to_path_buf(),
        threads,
    })
}
// :: ∎

fn parse_arg_type(s: &str) -> Result<ArgType, String> {
    match s.trim().to_ascii_lowercase().as_str() {
        "string" => Ok(ArgType::String),
        "int" => Ok(ArgType::Int),
        "bool" => Ok(ArgType::Bool),
        _ => Err(format!("unknown arg type: {}", s)),
    }
}

fn validate_arg_default(spec: &ArgSpec) -> Result<(), String> {
    match spec.ty {
        ArgType::String => Ok(()),
        ArgType::Int => {
            if spec.default.trim().is_empty() {
                Ok(())
            } else {
                spec.default
                    .parse::<i64>()
                    .map(|_| ())
                    .map_err(|_| format!("default expects int, got {}", spec.default))
            }
        }
        ArgType::Bool => {
            let vv = spec.default.to_ascii_lowercase();
            if vv.is_empty() || vv == "true" || vv == "false" || vv == "1" || vv == "0" {
                Ok(())
            } else {
                Err(format!("default expects bool, got {}", spec.default))
            }
        }
    }
}

fn toml_value_to_string(v: Option<toml::Value>) -> String {
    match v {
        Some(toml::Value::String(s)) => s,
        Some(toml::Value::Integer(i)) => i.to_string(),
        Some(toml::Value::Float(f)) => f.to_string(),
        Some(toml::Value::Boolean(b)) => b.to_string(),
        Some(other) => other.to_string(),
        None => String::new(),
    }
}

fn ensure_safe_rel_path(file: &str) -> Result<(), String> {
    let p = Path::new(file);

    if p.is_absolute() {
        return Err("absolute paths are not allowed".to_string());
    }

    for c in p.components() {
        if matches!(c, Component::ParentDir) {
            return Err("parent dir '..' is not allowed".to_string());
        }
    }

    Ok(())
}
