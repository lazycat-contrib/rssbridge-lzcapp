#!/bin/sh
# RSS-Bridge fetches whatever URL a caller asks it to, so an open instance acts
# as an outbound proxy on your server. Upstream ships Basic auth disabled by
# default; this wrapper always enables it from the deployment parameters and
# refuses to start without usable credentials.
#
# The upstream entrypoint copies anything found in /config/ into /app at start,
# so the rendered config is written there. It lives on tmpfs under /run and is
# symlinked in, keeping the credential out of the package and off any volume.
set -eu

USER_NAME="${RSSBRIDGE_USER:-}"
USER_PASS="${RSSBRIDGE_PASS:-}"

fail() {
    echo "[rss-bridge] refusing to start: $1" >&2
    # Never echo the offending value itself.
    exit 1
}

[ -n "$USER_NAME" ] || fail "RSSBRIDGE_USER must be set"
[ -n "$USER_PASS" ] || fail "RSSBRIDGE_PASS must be set"

# The config is an INI file; keep values inside a safe charset so a stray quote
# or newline cannot break the section or inject other keys.
case "$USER_NAME" in
    *[!A-Za-z0-9_.@-]*) fail "RSSBRIDGE_USER may only contain letters, digits and _ . @ -" ;;
esac
case "$USER_PASS" in
    *[!A-Za-z0-9_.~!@#%^+=-]*) fail "RSSBRIDGE_PASS contains unsupported characters" ;;
esac
[ "${#USER_PASS}" -ge 12 ] || fail "RSSBRIDGE_PASS must be at least 12 characters"

RENDER_DIR=/run/rssbridge
CONF="$RENDER_DIR/config.ini.php"
mkdir -p "$RENDER_DIR"
chmod 700 "$RENDER_DIR"

{
    printf '%s\n' '; generated at container start; not persisted'
    printf '%s\n' 'enabled_bridges[] = *'
    printf '%s\n' 'timezone = "Asia/Shanghai"'
    printf '%s\n' ''
    printf '%s\n' '[authentication]'
    printf '%s\n' 'enable = true'
    printf 'username = "%s"\n' "$USER_NAME"
    printf 'password = "%s"\n' "$USER_PASS"
} > "$CONF"
chmod 644 "$CONF"

# The entrypoint copies files out of /config, so expose the rendered file there.
mkdir -p /config
ln -sf "$CONF" /config/config.ini.php

exec /app/docker-entrypoint.sh
