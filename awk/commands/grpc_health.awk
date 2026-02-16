BEGIN { FS="\t"; OFS="\t" }
NF >= 4 {
  endpoint=$1
  status=toupper($2)
  latency=$3
  source=$4
  print endpoint, status, latency, source
}
