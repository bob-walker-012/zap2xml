#!/bin/sh
# Container health: output file exists, starts like XMLTV, and is not stale.
set -u
: "${OUTPUT_FILE:=/data/xmltv.xml}"
: "${SLEEPTIME:=43200}"

[ -s "$OUTPUT_FILE" ] || { echo "missing: $OUTPUT_FILE"; exit 1; }
head -c 200 "$OUTPUT_FILE" | grep -q "<tv " || { echo "not XMLTV: $OUTPUT_FILE"; exit 1; }

# stale = older than two refresh cycles + 30 min grace
MAX_AGE=$(( SLEEPTIME * 2 + 1800 ))
NOW=$(date +%s)
MTIME=$(date -r "$OUTPUT_FILE" +%s 2>/dev/null || stat -c %Y "$OUTPUT_FILE")
AGE=$(( NOW - MTIME ))
if [ "$AGE" -gt "$MAX_AGE" ]; then
  echo "stale: ${AGE}s old (limit ${MAX_AGE}s)"
  exit 1
fi
echo "ok: ${AGE}s old"
exit 0
