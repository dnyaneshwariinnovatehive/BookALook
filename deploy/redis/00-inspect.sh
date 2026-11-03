#!/usr/bin/env bash
# BookALook — Phase 1, step 0: READ-ONLY inspection of the VPS before Redis.
#
# Changes nothing. Prints no secrets (no .env values, no passwords).
# Run as root (or with sudo) and send back the whole output:
#
#   sudo bash 00-inspect.sh 2>&1 | tee /tmp/bookalook-redis-inspect.txt
#
set -u
export LC_ALL=C

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "Host"
hostnamectl 2>/dev/null | grep -E 'Operating System|Kernel|Architecture' || uname -a
uptime

section "Memory and CPU"
free -m
nproc
grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
top -bn1 | head -15

section "Disk"
df -h / /var/lib 2>/dev/null

section "Existing Redis / Valkey binaries"
for b in redis-server redis-cli valkey-server valkey-cli keydb-server; do
  if have "$b"; then echo "$b: $(command -v "$b") — $("$b" --version 2>/dev/null | head -1)"; else echo "$b: not installed"; fi
done

section "Installed Redis / Valkey / PHP-redis packages"
dpkg -l 2>/dev/null | awk '/^ii/ && ($2 ~ /redis|valkey|keydb/) {print $2, $3}'

section "Available packages (apt-cache policy, no install)"
for p in redis-server valkey-server valkey-redis-compat php8.2-redis php-redis; do
  echo "--- $p"; apt-cache policy "$p" 2>/dev/null | head -4
done
echo "--- configured apt sources mentioning ondrej/redis/valkey"
grep -rhsE 'ondrej|redis|valkey' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -v '^#' | sed 's/signed-by=[^]]*//'

section "Redis / Valkey processes and listening ports"
ps -eo pid,user,rss,args | grep -Ei '[r]edis|[v]alkey' || echo "no redis/valkey processes"
ss -ltnp 2>/dev/null | grep -E ':(6379|6380|26379)\b' || echo "nothing listening on 6379/6380/26379"

section "systemd units mentioning redis / valkey"
systemctl list-unit-files 2>/dev/null | grep -Ei 'redis|valkey' || echo "none"
systemctl list-units --all 2>/dev/null | grep -Ei 'redis|valkey' || true

section "Existing Redis / Valkey config and data directories"
ls -la /etc/redis /etc/valkey /var/lib/redis /var/lib/valkey /var/log/redis /var/log/valkey 2>&1 | head -40

section "PHP CLI"
have php && php -v | head -1
have php && php -r 'echo "redis extension (CLI): ", var_export(extension_loaded("redis"), true), PHP_EOL;'
have php && php -m | grep -iE '^(redis|igbinary|msgpack)$' || echo "no redis/igbinary/msgpack module in CLI"
ls /usr/bin/php* 2>/dev/null

section "PHP-FPM"
systemctl list-units --type=service 2>/dev/null | grep -E 'php.*fpm' || echo "no php-fpm units"
for f in /usr/sbin/php-fpm*; do [ -x "$f" ] && { echo "$f: $("$f" -v | head -1)"; "$f" -m 2>/dev/null | grep -iE '^redis$' || echo "  redis NOT loaded in $f"; }; done
ls /etc/php/*/fpm/conf.d/ 2>/dev/null | grep -i redis || echo "no redis ini in any fpm conf.d"
echo "--- which FPM socket Nginx uses"
grep -rhsE 'fastcgi_pass' /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | sort -u

section "Nginx in front (CDN / proxy check for rate-limit IPs)"
grep -rhsE 'real_ip_header|set_real_ip_from|X-Forwarded-For|proxy_set_header' /etc/nginx/ 2>/dev/null | sort -u | head -20
grep -rhsE 'server_name' /etc/nginx/sites-enabled/ 2>/dev/null | sort -u

section "Supervisor / queue workers (inspection only)"
have supervisorctl && supervisorctl status 2>&1 | head -20 || echo "supervisor not installed"
ls /etc/supervisor/conf.d/ 2>/dev/null
have pm2 && pm2 ls 2>/dev/null | head -20
ps -eo pid,user,etime,args | grep -E '[a]rtisan (queue|schedule)' || echo "no artisan queue/schedule processes running"
crontab -l -u www-data 2>/dev/null | grep -v '^#'; crontab -l 2>/dev/null | grep -v '^#'

section "Laravel app (paths and NON-SECRET settings only)"
for d in /var/www/bookalook/backend /var/www/bookalook /var/www/html/backend /var/www/*/backend; do
  [ -f "$d/artisan" ] && APP="$d" && break
done
if [ -n "${APP:-}" ]; then
  echo "app: $APP"
  # Only these keys, never their secrets.
  grep -E '^(APP_ENV|APP_DEBUG|CACHE_STORE|QUEUE_CONNECTION|SESSION_DRIVER|DB_CONNECTION|REDIS_CLIENT|REDIS_HOST|REDIS_PORT|WHATSAPP_DRIVER)=' "$APP/.env" 2>/dev/null
  echo "REDIS_PASSWORD set: $(grep -qE '^REDIS_PASSWORD=.+' "$APP/.env" 2>/dev/null && echo yes || echo no)"
  (cd "$APP" && php artisan --version 2>/dev/null)
else
  echo "Laravel app not found in the usual places — please tell me the path."
fi

section "Kernel settings Redis cares about"
sysctl vm.overcommit_memory net.core.somaxconn vm.swappiness 2>/dev/null
echo "THP enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
echo "THP defrag:  $(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)"
ls /etc/sysctl.d/ 2>/dev/null

section "Firewall"
have ufw && ufw status verbose 2>&1 | head -30 || echo "ufw not installed"
have nft && nft list ruleset 2>/dev/null | grep -E '6379|6380' || echo "no nftables rules mentioning 6379/6380"

section "PostgreSQL (status only, nothing restarted)"
systemctl list-units --type=service 2>/dev/null | grep -i postgres || echo "no postgresql unit"

echo
echo "Inspection finished. Nothing was changed."
