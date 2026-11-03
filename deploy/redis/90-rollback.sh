#!/usr/bin/env bash
# BookALook — Phase 1 rollback: remove the two BookALook Redis instances.
#
#   sudo FLAVOR=valkey PHPV=8.2 bash 90-rollback.sh
#
# Safe while the Laravel app still uses its database cache and queue (Phase 1):
# nothing in the app talks to these instances yet.
#
# Data is MOVED to /root/bookalook-redis-rollback-<time>, never deleted.
# Packages are only removed if you answer yes (removing php-redis needs a
# graceful PHP-FPM reload, which it also asks about).
#
set -euo pipefail
FLAVOR="${FLAVOR:?set FLAVOR=valkey or FLAVOR=redis}"
PHPV="${PHPV:-8.2}"
PKG=$([ "$FLAVOR" = valkey ] && echo valkey-server || echo redis-server)
DEFAULT_UNIT=$PKG.service
KEEP=/root/bookalook-redis-rollback-$(date +%Y%m%d-%H%M%S)
ask() { printf '%s [yes/no]: ' "$1"; read -r a; [ "$a" = yes ]; }

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# Refuse if the app has been switched to Redis (that is a Phase 2+ rollback first).
for d in /var/www/bookalook/backend /var/www/bookalook /var/www/*/backend; do [ -f "$d/artisan" ] && APP=$d && break; done
if [ -n "${APP:-}" ] && grep -qE '^(CACHE_STORE|QUEUE_CONNECTION|SESSION_DRIVER)=redis' "$APP/.env"; then
  echo "STOP: $APP/.env uses redis. Switch the app back to database and clear config first."; exit 1
fi

mkdir -p "$KEEP"
echo ">>> Stopping and disabling bookalook-redis@cache and @state"
for i in cache state; do
  systemctl disable --now "bookalook-redis@$i" 2>/dev/null || true
done
rm -f /etc/systemd/system/bookalook-redis@.service
systemctl daemon-reload

echo ">>> Moving config, secrets, data and logs to $KEEP"
for p in /etc/bookalook-redis /var/lib/bookalook-redis /var/log/bookalook-redis; do
  [ -e "$p" ] && mv "$p" "$KEEP/" && echo "  moved $p"
done
chmod -R go-rwx "$KEEP"

echo ">>> Kernel setting"
if [ -e /etc/sysctl.d/60-bookalook-redis.conf ]; then
  mv /etc/sysctl.d/60-bookalook-redis.conf "$KEEP/"
  # Back to the value saved before install (Ubuntu's default is 0).
  before=$(grep -h 'vm.overcommit_memory' /root/bookalook-redis-backup-*/sysctl.d/* 2>/dev/null | tail -1 | awk -F= '{gsub(/ /,"",$2); print $2}')
  sysctl -w vm.overcommit_memory="${before:-0}"
fi

echo ">>> Service user"
id bookalook-redis >/dev/null 2>&1 && userdel bookalook-redis && echo "  removed user bookalook-redis"

systemctl unmask "$DEFAULT_UNIT" 2>/dev/null || true
echo "  stock $DEFAULT_UNIT unmasked (left disabled)."

if ask "Also remove the $PKG and php$PHPV-redis packages?"; then
  printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod 755 /usr/sbin/policy-rc.d
  trap 'rm -f /usr/sbin/policy-rc.d' EXIT
  apt-get remove -y "$PKG" "php$PHPV-redis"
  rm -f /usr/sbin/policy-rc.d; trap - EXIT
  if ask "Gracefully reload php$PHPV-fpm now so it unloads the redis extension? (no dropped requests)"; then
    systemctl reload "php$PHPV-fpm"
  else
    echo "  Remember: sudo systemctl reload php$PHPV-fpm"
  fi
fi

echo "Rollback done. Kept: $KEEP (delete it yourself once you are sure)."
