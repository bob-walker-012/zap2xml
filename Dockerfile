FROM alpine:3.21

LABEL org.opencontainers.image.title="zap2xml" \
      org.opencontainers.image.description="Gracenote/TV Listings grid-affiliates XMLTV grabber with sleep loop, HTTP output and PUID/PGID support for Unraid" \
      org.opencontainers.image.source="https://github.com/bob-walker-012/zap2xml" \
      org.opencontainers.image.licenses="MIT"

ENV OUTPUT_FILE=/data/xmltv.xml \
    AFFILIATE_ID=orbebb \
    OPT_ARGS="-U -D -I" \
    SLEEPTIME=43200 \
    ENABLE_HTTP=true \
    HTTP_PORT=8080 \
    PUID=99 \
    PGID=100 \
    UMASK=022 \
    TZ=America/New_York

RUN apk add --no-cache \
      perl perl-encode perl-html-parser perl-http-cookies \
      perl-lwp-useragent-determined perl-json perl-json-xs \
      perl-lwp-protocol-https perl-uri perl-libwww perl-mozilla-ca \
      perl-net-http perl-io-socket-ssl perl-net-ssleay perl-net-libidn \
      perl-compress-raw-zlib \
      xmltv tzdata ca-certificates su-exec busybox

RUN mkdir -p /data/cache && chown -R 99:100 /data

COPY zap2xml.pl /usr/local/bin/zap2xml.pl
COPY entry.sh /usr/local/bin/entry.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod 755 /usr/local/bin/zap2xml.pl \
              /usr/local/bin/entry.sh \
              /usr/local/bin/healthcheck.sh

VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=5m --timeout=15s --start-period=10m --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

CMD ["/usr/local/bin/entry.sh"]
