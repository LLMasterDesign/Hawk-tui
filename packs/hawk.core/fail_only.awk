# ▛▞// fail_only :: hawk.thread.fail_only
# @ctx ⫸ [awk.tsv.hawkframe]
# @ctx ⫸ [awk.filter.level]
# @ctx ⫸ [awk.arg.scope]
BEGIN {
  FS = "\t"; OFS = "\t";
}

# Columns:
# 1 ts, 2 kind, 3 scope, 4 id, 5 level, 6 msg, 7 kv
# Vars:
# - scope (optional)
{
  lvl = tolower($5);
  if (lvl != "fail" && lvl != "warn") next;

  if (scope != "" && $3 != scope) next;

  print $0;
}
# :: ∎
