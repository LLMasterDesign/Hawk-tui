BEGIN {
  FS="|"
  now=systime()
}

NF >= 2 {
  ts=$1+0
  stream=$2
  if (ts > latest[stream]) {
    latest[stream]=ts
  }
  count[stream]++
}

END {
  has=0
  for (s in latest) {
    has=1
    lag=now-latest[s]
    if (lag < 0) lag=0
    printf "%s\tlag=%ss\tevents=%d\tlast_epoch=%d\n", s, lag, count[s], latest[s]
  }
  if (!has) {
    print "stream\tlag=n/a\tevents=0\tlast_epoch=0"
  }
}
