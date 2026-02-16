# Hawk awk command book (HawkFrame TSV)

HawkFrame columns (TSV):
1 ts
2 kind
3 scope
4 id
5 level
6 msg
7 kv

Run tips:
- Always use: -F '\t'
- Use: OFS="\t" when re-emitting TSV

## Inspect fields
awk -F '\t' '{print "ts="$1,"kind="$2,"scope="$3,"id="$4,"level="$5}' file.tsv

## Filter failures
awk -F '\t' 'tolower($5)=="fail"{print}' file.tsv

## Filter service scope only
awk -F '\t' '$3=="service"{print}' file.tsv

## Filter by kind
awk -F '\t' '$2=="HEALTH"{print}' file.tsv

## Print compact summary line
awk -F '\t' '{printf "%s %s %s:%s %s %s\n",$1,$2,$3,$4,$5,$6}' file.tsv

## Count levels
awk -F '\t' '{c[tolower($5)]++} END{for(k in c) printf "%-7s %d\n",k,c[k]}' file.tsv | sort

## Count by kind then level
awk -F '\t' '{k=$2 ":" tolower($5); c[k]++} END{for(x in c) print x,c[x]}' file.tsv | sort

## Count entities seen (unique scope:id)
awk -F '\t' '{u[$3 ":" $4]=1} END{print "unique_entities", length(u)}' file.tsv

## Latest event per entity (prints last line for each scope:id)
awk -F '\t' '{key=$3 ":" $4; last[key]=$0} END{for(k in last) print last[k]}' file.tsv

## Show last failure per entity (if any)
awk -F '\t' 'tolower($5)=="fail"{key=$3 ":" $4; lastfail[key]=$0} END{for(k in lastfail) print lastfail[k]}' file.tsv

## Extract kv values (example: status=, trace_id=)
# kv bag is col 7: key=value;key=value
# This extracts status if present.
awk -F '\t' '
function kv_get(kv, key,   n,i,pair,k,v) {
  n=split(kv, parts, ";");
  for(i=1;i<=n;i++){
    pair=parts[i];
    sub(/^ +/,"",pair); sub(/ +$/,"",pair);
    split(pair, kvp, "=");
    k=kvp[1]; v=kvp[2];
    if(k==key) return v;
  }
  return "";
}
{
  status=kv_get($7,"status");
  if(status!="") print $1,$3,$4,$5,status,$6
}' OFS="\t" file.tsv

## Build a health table (entity, level, state guess by age) using local time only
# Note: awk alone does not parse ISO timestamps easily without gawk extensions or helper tools.
# Use this when ts is blank and hawkd stamps a unix epoch into kv: t_unix=...
awk -F '\t' '
function kv_get(kv, key,   n,i,pair,k,v) {
  n=split(kv, parts, ";");
  for(i=1;i<=n;i++){
    pair=parts[i];
    sub(/^ +/,"",pair); sub(/ +$/,"",pair);
    split(pair, kvp, "=");
    k=kvp[1]; v=kvp[2];
    if(k==key) return v;
  }
  return "";
}
{
  key=$3 ":" $4;
  t=kv_get($7,"t_unix")+0;
  if(t>0){
    last[key]=t;
    level[key]=tolower($5);
    msg[key]=$6;
  }
}
END{
  now=systime();
  for(k in last){
    age=now-last[k];
    state="dream";
    if(age>=30) state="dead";
    else if(age>=10) state="stale";
    printf "%-30s %-6s %-6s %4ds %s\n", k, level[k], state, age, msg[k];
  }
}' file.tsv | sort

## Pretty print into aligned columns (terminal table)
awk -F '\t' '
BEGIN{printf "%-20s %-10s %-10s %-20s %-6s %s\n","ts","kind","scope","id","lvl","msg"}
{printf "%-20s %-10s %-10s %-20s %-6s %s\n",$1,$2,$3,$4,$5,$6}
' file.tsv

## Tail only warnings and failures
tail -F events.tsv | awk -F '\t' 'tolower($5)=="warn" || tolower($5)=="fail"{print}'
