BEGIN {
  err=0
  warn=0
  info=0
}

{
  line=toupper($0)
  if (line ~ /ERROR/) err++
  if (line ~ /WARN/) warn++
  if (line ~ /INFO/) info++
}

END {
  printf "ERROR\t%d\n", err
  printf "WARN\t%d\n", warn
  printf "INFO\t%d\n", info
}
