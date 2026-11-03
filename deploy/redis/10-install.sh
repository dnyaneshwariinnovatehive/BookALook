#!/usr/bin/env bash
# BookALook — Phase 1, step 1: install two Redis instances (cache 6379, state 6380)
# and the PhpRedis extension. Does NOT touch the Laravel app, its .env, its cache
# or its queues; the app keeps using its database cache and queue.
#
#   sudo FLAVOR=valkey PHPV=8.2 bash 10-install.sh      # or FLAVOR=redis
#
# FLAVOR is chosen from 00-inspect.sh output (what apt offers and its licence).
# Safe to re-run: existing files are never overwritten, and it stops before any
# step that touches a running service unless you type "yes".
#
# Gates (it asks before each):
#   A. apt install of the server package and php${PHPV}-redis
#   B. kernel: vm.overcommit_memory=1 (persisted in /etc/sysctl.d)
#   C. graceful reload of php${PHPV}-fpm so FPM loads the redis extension
#
set -euo pipefail
umask 077

FLAVOR="${FLAVOR:?set FLAVOR=valkey or FLAVOR=redis (see 00-inspect.sh output)}"
PHPV="${PHPV:-8.2}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ETC=/etc/bookalook-redis
DATA=/var/lib/bookalook-redis
LOGS=/var/log/bookalook-redis
SECRETS=$ETC/secrets
SVC_USER=bookalook-redis
BACKUP=/root/bookalook-redis-backup-$(date +%Y%m%d-%H%M%S)

case "$FLAVOR" in
  valkey) PKG=valkey-server; SERVER_BIN=/usr/bin/valkey-server; CLI=valkey-cli; DEFAULT_UNIT=valkey-server.service ;;
  redis)  PKG=redis-server;  SERVER_BIN=/usr/bin/redis-server;  CLI=redis-cli;  DEFAULT_UNIT=redis-server.service ;;
  *) echo "FLAVOR must be valkey or redis"; exit 1 ;;
esac

say()  { printf '\n>>> %s\n' "$*"; }
die()  { printf '\nSTOP: %s\n' "$*" >&2; exit 1; }
gate() {
  printf '\n----- APPROVAL GATE %s -----\n%s\nType yes to continue, anything else to stop: ' "$1" "$2"
  read -r answer
  [ "$answer" = "yes" ] || die "stopped at gate $1 — nothing after this point was done."
}
# Install a file only if it is not there yet; never overwrite.
put() { # src dest mode owner
  if [ -e "$2" ]; then
    if cmp -s "$1" "$2"; then echo "  unchanged: $2"; else echo "  EXISTS, left as is (differs from repo): $2"; fi
  else
    install -m "$3" -o "${4%%:*}" -g "${4##*:}" "$1" "$2"; echo "  installed: $2"
  fi
}

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)."

# --- 0. Preflight ------------------------------------------------------------
say "Preflight"
for port in 6379 6380; do
  if ss -ltnH "( sport = :$port )" | grep -q .; then
    if systemctl is-active --quiet "bookalook-redis@$([ $port = 6379 ] && echo cache || echo state)"; then
      echo "  port $port is ours already (re-run)"
    else
      die "something else is listening on port $port — see 00-inspect.sh; not installing over it."
    fi
  fi
done
mkdir -p "$BACKUP"
cp -a /etc/sysctl.d "$BACKUP/" 2>/dev/null || true
[ -d /etc/php/$PHPV ] && cp -a /etc/php/$PHPV "$BACKUP/php-$PHPV" || true
echo "  backup of sysctl.d and /etc/php/$PHPV: $BACKUP"
free -m | tee "$BACKUP/free-before.txt"

# --- A. Packages ---------------------------------------------------------------
if ! dpkg -s "$PKG" >/dev/null 2>&1 || ! dpkg -s "php$PHPV-redis" >/dev/null 2>&1; then
  apt-cache policy "$PKG" "php$PHPV-redis" | sed -n '1,12p'
  # Dry run first: refuse if apt would UPGRADE or REMOVE anything already
  # installed (e.g. pull a newer php8.2-common). Only new packages may appear.
  sim=$(apt-get install -s --no-install-recommends "$PKG" "php$PHPV-redis")
  echo "$sim" | grep -E '^(Inst|Remv) ' | sed 's/^/  would: /'
  if echo "$sim" | grep -qE '^Remv |^Inst [^ ]+ \['; then
    die "apt would upgrade or remove an installed package (lines with [old version] or Remv above). Not installing; send me this output."
  fi
  gate A "Install $PKG and php$PHPV-redis with apt.
Package scripts are prevented from starting or restarting ANY service during the
install (policy-rc.d), so neither the stock $DEFAULT_UNIT on 6379 nor PHP-FPM is
touched. The stock unit is then disabled and masked; its config is left in place."
  printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod 755 /usr/sbin/policy-rc.d
  trap 'rm -f /usr/sbin/policy-rc.d' EXIT
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$PKG" "php$PHPV-redis"
  rm -f /usr/sbin/policy-rc.d; trap - EXIT
else
  echo "  $PKG and php$PHPV-redis already installed"
fi
systemctl disable --now "$DEFAULT_UNIT" 2>/dev/null || true
systemctl mask "$DEFAULT_UNIT" 2>/dev/null || true
echo "  stock $DEFAULT_UNIT: $(systemctl is-enabled "$DEFAULT_UNIT" 2>/dev/null || true)"
"$SERVER_BIN" --version

# --- Service user and directories -------------------------------------------
say "User and directories"
id "$SVC_USER" >/dev/null 2>&1 || useradd --system --no-create-home --home-dir "$DATA" --shell /usr/sbin/nologin "$SVC_USER"
install -d -m 0755 -o root -g root "$ETC"
install -d -m 0700 -o root -g root "$SECRETS"
for i in cache state; do
  install -d -m 0750 -o root -g "$SVC_USER" "$ETC/$i"
  install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$DATA/$i"
done
install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$DATA" "$LOGS"
chown "$SVC_USER:$SVC_USER" "$DATA"

# --- Config files ------------------------------------------------------------
say "Configuration"
put "$HERE/redis-cache.conf" "$ETC/cache/redis.conf" 0640 "root:$SVC_USER"
put "$HERE/redis-state.conf" "$ETC/state/redis.conf" 0640 "root:$SVC_USER"

# --- Credentials and ACL files ----------------------------------------------
# Passwords: random, stored root-only in $SECRETS. The ACL files hold only their
# SHA-256 (the #hash form), so the server never has them in plain text.
say "ACL users (passwords are generated and never printed)"
APP_RULES='~* &* +@all -flushall -flushdb -config -debug -shutdown -acl -module -monitor -replicaof -slaveof -failover -sync -psync -save -bgsave -bgrewriteaof -migrate -restore -swapdb'
for i in cache state; do
  for who in app admin; do
    f="$SECRETS/$i-$who.pass"
    [ -s "$f" ] || { openssl rand -hex 32 > "$f"; chmod 600 "$f"; echo "  generated $f"; }
  done
  acl="$ETC/$i/users.acl"
  if [ -e "$acl" ]; then
    echo "  EXISTS, left as is: $acl"
  else
    app_hash=$(tr -d '\n' < "$SECRETS/$i-app.pass" | sha256sum | cut -d' ' -f1)
    adm_hash=$(tr -d '\n' < "$SECRETS/$i-admin.pass" | sha256sum | cut -d' ' -f1)
    {
      echo "user default off resetchannels -@all"
      echo "user bookalook_app on #$app_hash $APP_RULES"
      echo "user bookalook_admin on #$adm_hash ~* &* +@all"
    } > "$acl"
    chown "root:$SVC_USER" "$acl"; chmod 0640 "$acl"
    echo "  wrote $acl (hashes only)"
  fi
done

# --- B. Kernel ---------------------------------------------------------------
SYSCTL=/etc/sysctl.d/60-bookalook-redis.conf
if [ "$(sysctl -n vm.overcommit_memory)" != "1" ] || [ ! -e "$SYSCTL" ]; then
  echo "  vm.overcommit_memory is now $(sysctl -n vm.overcommit_memory)"
  gate B "Set vm.overcommit_memory=1 now and on every boot ($SYSCTL).
Redis needs it so background saves (fork) do not fail under memory pressure.
No other kernel setting is changed. Transparent huge pages are NOT changed on
the host: both instances turn THP off for themselves (disable-thp yes)."
  printf '# Redis: background save (fork) must not fail. See deploy/redis.\nvm.overcommit_memory = 1\n' > "$SYSCTL"
  chmod 644 "$SYSCTL"
  sysctl -p "$SYSCTL"
fi
echo "  THP on host (unchanged): $(cat /sys/kernel/mm/transparent_hugepage/enabled)"

# --- systemd -----------------------------------------------------------------
say "systemd units"
UNIT=/etc/systemd/system/bookalook-redis@.service
tmp=$(mktemp); sed "s#@SERVER_BIN@#$SERVER_BIN#" "$HERE/bookalook-redis@.service" > "$tmp"
put "$tmp" "$UNIT" 0644 root:root; rm -f "$tmp"
systemctl daemon-reload
for i in cache state; do
  systemctl enable --now "bookalook-redis@$i"
  sleep 1
  systemctl is-active --quiet "bookalook-redis@$i" || { journalctl -u "bookalook-redis@$i" -n 30 --no-pager; die "bookalook-redis@$i did not start"; }
  echo "  bookalook-redis@$i: $(systemctl is-active bookalook-redis@$i), enabled: $(systemctl is-enabled bookalook-redis@$i)"
done

# --- C. PHP-FPM ----------------------------------------------------------------
say "PhpRedis"
php -r 'echo "CLI redis loaded: ", var_export(extension_loaded("redis"), true), " (phpredis ", phpversion("redis") ?: "-", ")", PHP_EOL;'
FPM_BIN=/usr/sbin/php-fpm$PHPV
if "$FPM_BIN" -m 2>/dev/null | grep -qi '^redis$'; then
  echo "  php-fpm$PHPV will load redis on its next start/reload"
fi
if systemctl is-active --quiet "php$PHPV-fpm"; then
  gate C "Gracefully reload php$PHPV-fpm so the running FPM loads the redis extension.
'systemctl reload' lets busy workers finish their requests and starts new ones;
Nginx keeps serving and no request is dropped. PostgreSQL and Nginx are not touched.
(If you prefer, answer no and reload in a quiet minute yourself:
 sudo systemctl reload php$PHPV-fpm)"
  systemctl reload "php$PHPV-fpm"
  sleep 1
  systemctl is-active "php$PHPV-fpm"
fi

free -m | tee "$BACKUP/free-after.txt"
say "Install finished. Now run: sudo bash $HERE/30-verify.sh"
echo "Laravel .env, cache and queue were not changed."
