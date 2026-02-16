# ▛▞// scope_counts :: hawk.thread.scope_counts
# @ctx ⫸ [awk.aggregate.count]
# @ctx ⫸ [awk.emit.hawkframe]
# @ctx ⫸ [awk.arg.window_s]
BEGIN {
  FS = "\t"; OFS = "\t";
  if (window_s == "") window_s = 10;
  next_emit = systime() + window_s;
}

function emit(now, scope, lvl, c) {
  # Emit a synthetic HawkFrame TSV line:
  # ts  kind   scope  id            level msg    kv
  ts = $1;
  if (ts == "") ts = now;

  kind = "RECEIPT_EVENT";
  out_scope = "awk";
  id = "scope_counts";

  level = "info";
  msg = "count";
  kv = "src_scope=" scope ";src_level=" lvl ";count=" c ";window_s=" window_s;

  print ts, kind, out_scope, id, level, msg, kv;
}

{
  s = $3;
  l = tolower($5);
  key = s "|" l;
  counts[key] += 1;

  if (systime() >= next_emit) {
    now = $1;
    if (now == "") now = "1970-01-01T00:00:00Z";

    for (k in counts) {
      split(k, parts, "|");
      emit(now, parts[1], parts[2], counts[k]);
      counts[k] = 0;
    }

    next_emit = systime() + window_s;
  }
}
# :: ∎
