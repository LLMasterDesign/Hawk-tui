# ▛▞// systemd_focus :: hawk.thread.systemd_focus
# @ctx ⫸ [awk.filter.scope]
# @ctx ⫸ [awk.arg.id_prefix]
BEGIN {
  FS = "\t"; OFS = "\t";
}

{
  if ($3 != "systemd") next;

  if (id_prefix != "") {
    if (index($4, id_prefix) != 1) next;
  }

  print $0;
}
# :: ∎
