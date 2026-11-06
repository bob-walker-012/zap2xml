#!/bin/sh
# zap2xml container entrypoint
# Grabs TV listings from tvlistings.gracenote.com (grid-affiliates affiliate id)
# and writes XMLTV to OUTPUT_FILE on a sleep loop.
set -u

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"; }

# ---------------------------------------------------------------- defaults
: "${USERNAME:=}"
: "${PASSWORD:=}"
: "${USERNAME2:=}"
: "${PASSWORD2:=}"
: "${LINEUP_ID:=}"
: "${ZIPCODE:=}"
: "${AFFILIATE_ID:=orbebb}"
: "${OUTPUT_FILE:=/data/xmltv.xml}"
: "${OPT_ARGS:=-U -D -I}"
: "${SLEEPTIME:=43200}"
: "${RUN_ONCE:=false}"
: "${ENABLE_HTTP:=true}"
: "${HTTP_PORT:=8080}"
: "${CACHE_DIR:=/data/cache}"
: "${PUID:=99}"
: "${PGID:=100}"
: "${UMASK:=022}"
umask "$UMASK"

OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

# ------------------------------------------------------- permissions / drop
if [ "$(id -u)" = "0" ]; then
  chown -R "$PUID:$PGID" "$OUTPUT_DIR" "$CACHE_DIR" 2>/dev/null || true
  RUNAS="su-exec $PUID:$PGID"
else
  RUNAS=""
fi

# ------------------------------------------------------------------ httpd
if [ "$ENABLE_HTTP" = "true" ]; then
  log "Serving $OUTPUT_DIR on port $HTTP_PORT"
  httpd -p "$HTTP_PORT" -h "$OUTPUT_DIR" || log "WARN: could not start httpd on $HTTP_PORT"
fi

# --------------------------------------------------------------- one grab
# run_grab <user> <pass> <out> <cache>
run_grab() {
  _u=$1; _p=$2; _out=$3; _cache=$4
  set --
  if [ -n "$_u" ] && [ -n "$_p" ]; then
    set -- "$@" -u "$_u" -p "$_p"
  elif [ -n "$LINEUP_ID" ] && [ -n "$ZIPCODE" ]; then
    set -- "$@" -Y "$LINEUP_ID" -Z "$ZIPCODE"
  else
    log "ERROR: set USERNAME+PASSWORD, or LINEUP_ID+ZIPCODE"
    return 1
  fi
  set -- "$@" -o "$_out.tmp" -c "$_cache" -Q "$AFFILIATE_ID"
  # shellcheck disable=SC2086
  $RUNAS zap2xml.pl "$@" $OPT_ARGS
  _rc=$?
  if [ "$_rc" -ne 0 ] || [ ! -s "$_out.tmp" ]; then
    log "ERROR: zap2xml.pl failed (exit $_rc)"
    rm -f "$_out.tmp"
    return 1
  fi
  mv -f "$_out.tmp" "$_out"
  log "Wrote $(du -h "$_out" | cut -f1) to $_out"
}

# ------------------------------------------------------------ refresh loop
while :; do
  START=$(date +%s)
  log "Starting EPG update (affiliate=$AFFILIATE_ID, lineup=${LINEUP_ID:-login})"

  if [ -n "$USERNAME2" ] && [ -n "$PASSWORD2" ]; then
    log "Second account configured - fetching and merging"
    run_grab "$USERNAME" "$PASSWORD" "$OUTPUT_DIR/.part1.xml" "$CACHE_DIR/cache1" || true
    run_grab "$USERNAME2" "$PASSWORD2" "$OUTPUT_DIR/.part2.xml" "$CACHE_DIR/cache2" || true
    if [ -s "$OUTPUT_DIR/.part1.xml" ] && [ -s "$OUTPUT_DIR/.part2.xml" ] \
       && command -v tv_sort >/dev/null 2>&1; then
      tv_sort "$OUTPUT_DIR/.part1.xml" --by-channel --output "$OUTPUT_DIR/.s1.xml" &&
        tv_sort "$OUTPUT_DIR/.part2.xml" --by-channel --output "$OUTPUT_DIR/.s2.xml" &&
        {
          if command -v tv_merge >/dev/null 2>&1; then
            tv_merge -i "$OUTPUT_DIR/.s1.xml" -m "$OUTPUT_DIR/.s2.xml" -o "$OUTPUT_FILE"
          else
            tv_cat "$OUTPUT_DIR/.s1.xml" "$OUTPUT_DIR/.s2.xml" > "$OUTPUT_FILE"
          fi
        } && log "Merged both accounts into $OUTPUT_FILE"
    elif [ -s "$OUTPUT_DIR/.part1.xml" ]; then
      mv -f "$OUTPUT_DIR/.part1.xml" "$OUTPUT_FILE"
    fi
    rm -f "$OUTPUT_DIR/.part1.xml" "$OUTPUT_DIR/.part2.xml" \
          "$OUTPUT_DIR/.s1.xml" "$OUTPUT_DIR/.s2.xml"
  else
    run_grab "$USERNAME" "$PASSWORD" "$OUTPUT_FILE" "$CACHE_DIR"
  fi

  if [ "$RUN_ONCE" = "true" ]; then
    log "RUN_ONCE=true - exiting"
    exit 0
  fi
  ELAPSED=$(( $(date +%s) - START ))
  NEXT=$(( SLEEPTIME - ELAPSED ))
  [ "$NEXT" -lt 60 ] && NEXT=60
  log "Next run in ${NEXT}s"
  sleep "$NEXT"
done
