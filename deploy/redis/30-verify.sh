#!/usr/bin/env bash
# BookALook — Phase 1, step 3: verify both Redis instances and PhpRedis.
#
#   sudo FLAVOR=valkey PHPV=8.2 bash 30-verify.sh
#
# Passwords are read from /etc/bookalook-redis/secrets and passed through the
# REDISCLI_AUTH environment variable, so they never appear in output or `ps`.
# Write tests use only keys under "bookalook:phase1:" and delete them after.
# The memory-limit tests run only while an instance holds no other keys.
#
set -uo pipefail
FLAVOR="${FLAVOR:?set FLAVOR=valkey or FLAVOR=redis}"
PHPV="${PHPV:-8.2}"
CLI=$([ "$FLAVOR" = valkey ] && echo valkey-cli || echo redis-cli)
SECRETS=/etc/bookalook-redis/secrets
T=bookalook:phase1
pass=0; fail=0
ok()  { echo "  PASS  $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

port_of() { [ "$1" = cache ] && echo 6379 || echo 6380; }
# r <instance> <app|admin> <redis args...>
r() { local i=$1 who=$2; shift 2
  local pw; pw="$(cat "$SECRETS/$i-$who.pass")"
  REDISCLI_AUTH="$pw" VALKEYCLI_AUTH="$pw" "$CLI" --no-auth-warning -h 127.0.0.1 -p "$(port_of "$i")" --user "bookalook_$who" "$@"; }
info() { r "$1" admin INFO "$2" | tr -d '\r' | grep "^$3:" | cut -d: -f2; }

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

for i in cache state; do
  P=$(port_of $i)
  echo; echo "===== $i (port $P) ====="

  # 1, 2: running, enabled, survives a restart
  check "1 service active"          systemctl is-active --quiet "bookalook-redis@$i"
  check "  enabled at boot"         systemctl is-enabled --quiet "bookalook-redis@$i"
  [ "$i" = state ] && r state app SET "$T:survives" yes EX 600 >/dev/null
  systemctl restart "bookalook-redis@$i"; sleep 2
  check "2 active after restart"    systemctl is-active --quiet "bookalook-redis@$i"
  if [ "$i" = state ]; then
    [ "$(r state app GET "$T:survives")" = yes ] && ok "  state key survived restart (AOF)" || bad "  state key lost on restart"
    r state app DEL "$T:survives" >/dev/null
  fi
  MAINPID=$(systemctl show -p MainPID --value "bookalook-redis@$i")
  kill -9 "$MAINPID" 2>/dev/null; sleep 4
  check "  restarted itself after a crash (kill -9)" systemctl is-active --quiet "bookalook-redis@$i"

  # 3, 4: ping, authentication
  [ "$(r $i app PING)" = PONG ] && ok "3 PING as bookalook_app" || bad "3 PING"
  out=$(REDISCLI_AUTH=wrong-password VALKEYCLI_AUTH=wrong-password "$CLI" --no-auth-warning -p "$P" --user bookalook_app PING 2>&1)
  echo "$out" | grep -qiE 'WRONGPASS|invalid|NOAUTH' && ok "4 wrong password refused" || bad "4 wrong password accepted: $out"
  out=$("$CLI" -p "$P" PING 2>&1)
  echo "$out" | grep -qiE 'NOAUTH|WRONGPASS|denied' && ok "  no-password (default user) refused" || bad "  default user answered: $out"

  # 5: ACL
  for cmd in FLUSHALL FLUSHDB "CONFIG GET maxmemory" "DEBUG SLEEP 0" "SHUTDOWN NOSAVE" "ACL LIST"; do
    out=$(r $i app $cmd 2>&1)
    echo "$out" | grep -qiE 'NOPERM|command not allowed' && ok "5 app user cannot: $cmd" || bad "5 app user CAN run: $cmd -> $out"
  done
  r $i app SET "$T:acl" 1 EX 60 >/dev/null && [ "$(r $i app GET "$T:acl")" = 1 ] && ok "  app user can SET/GET" || bad "  app user cannot SET/GET"
  r $i app DEL "$T:acl" >/dev/null
  r $i app EVAL "return 1" 0 >/dev/null 2>&1 && ok "  app user can run Lua (Laravel queues need it)" || bad "  app user cannot EVAL"
  [ "$(r $i admin CONFIG GET port | tail -1)" = "$P" ] && ok "  admin user can CONFIG GET" || bad "  admin CONFIG GET"
  r $i admin ACL LIST | sed -E 's/#[0-9a-f]{64}/#<hash>/g' | sed 's/^/        /'

  # 6: localhost only
  binds=$(ss -ltnH "( sport = :$P )" | awk '{print $4}' | sort -u | tr '\n' ' ')
  echo "$binds" | grep -vqE '(^| )(0\.0\.0\.0|\*|\[::\]):' && ok "6 listens only on: $binds" || bad "6 listening publicly: $binds"
  PUB=$(hostname -I | awk '{print $1}')
  timeout 3 bash -c "</dev/tcp/$PUB/$P" 2>/dev/null && bad "  reachable on public IP $PUB:$P" || ok "  not reachable on public IP $PUB:$P"
  if command -v ufw >/dev/null; then
    ufw status | grep -qE "^$P(/tcp)?\s+ALLOW" && bad "  ufw has an ALLOW rule for $P" || ok "  no ufw ALLOW rule for $P"
  fi

  # 7-10: memory policy and persistence
  pol=$(r $i admin CONFIG GET maxmemory-policy | tail -1)
  mem=$(r $i admin CONFIG GET maxmemory | tail -1)
  aof=$(r $i admin CONFIG GET appendonly | tail -1)
  save=$(r $i admin CONFIG GET save | tail -1)
  fsync=$(r $i admin CONFIG GET appendfsync | tail -1)
  if [ $i = cache ]; then
    [ "$pol" = allkeys-lru ] && ok "7 policy allkeys-lru" || bad "7 policy is $pol"
    [ "$mem" = 536870912 ] && ok "  maxmemory 512mb" || bad "  maxmemory is $mem"
    [ "$aof" = no ] && [ -z "$save" ] && ok "9 no persistence (appendonly no, save \"\")" || bad "9 persistence on: aof=$aof save=$save"
  else
    [ "$pol" = noeviction ] && ok "8 policy noeviction" || bad "8 policy is $pol"
    [ "$mem" = 268435456 ] && ok "  maxmemory 256mb" || bad "  maxmemory is $mem"
    [ "$aof" = yes ] && [ "$fsync" = everysec ] && [ -n "$save" ] && ok "10 AOF everysec + RDB ($save)" || bad "10 aof=$aof fsync=$fsync save=$save"
    [ "$(info state persistence aof_enabled)" = 1 ] && ok "  INFO aof_enabled:1" || bad "  INFO aof_enabled"
    [ "$(info state persistence aof_last_write_status)" = ok ] && ok "  last AOF write ok" || bad "  AOF write status"
  fi

  # 11: limits actually enforced — only on an empty instance, at a temporary 4mb
  keys=$(r $i admin DBSIZE)
  if [ "$keys" = 0 ]; then
    r $i admin CONFIG SET maxmemory 4mb >/dev/null
    blob=$(head -c 65536 /dev/zero | tr '\0' x)
    hit_oom=no
    for n in $(seq 1 200); do
      out=$(r $i app SET "$T:fill:$n" "$blob" 2>&1)
      echo "$out" | grep -q OOM && { hit_oom=yes; break; }
    done
    used=$(info $i memory used_memory); evicted=$(info $i stats evicted_keys)
    if [ $i = cache ]; then
      [ "$hit_oom" = no ] && [ "${evicted:-0}" -gt 0 ] && ok "11 at its limit the cache evicts (evicted_keys=$evicted)" || bad "11 cache: oom=$hit_oom evicted=$evicted"
    else
      [ "$hit_oom" = yes ] && ok "11 at its limit the state instance refuses writes (OOM), evicts nothing" || bad "11 state never refused a write"
    fi
    for k in $(r $i admin --scan --pattern "$T:*"); do r $i admin DEL "$k" >/dev/null; done
    r $i admin CONFIG SET maxmemory "$mem" >/dev/null
    [ "$(r $i admin CONFIG GET maxmemory | tail -1)" = "$mem" ] && ok "  maxmemory restored to $mem" || bad "  maxmemory NOT restored"
    [ $i = state ] && r state admin BGREWRITEAOF >/dev/null
  else
    echo "  SKIP  11 memory test: instance holds $keys keys (never tested against real data)"
  fi
  echo "  data dir: $(r $i admin CONFIG GET dir | tail -1), log: $(r $i admin CONFIG GET logfile | tail -1)"
  echo "  used_memory_human: $(info $i memory used_memory_human)  version: $(info $i server valkey_version || true) $(info $i server redis_version)"
done

echo; echo "===== PHP ====="
# 12: PHP CLI connects to both with the app user
for i in cache state; do
  out=$(BK_PASS="$(cat "$SECRETS/$i-app.pass")" BK_PORT=$(port_of $i) php -r '
    $r = new Redis();
    $r->connect("127.0.0.1", (int) getenv("BK_PORT"), 2.0);
    $r->auth(["bookalook_app", getenv("BK_PASS")]);
    echo $r->ping() ? "PONG" : "no";' 2>&1)
  [ "$out" = PONG ] || [ "$out" = 1 ] && ok "12 PHP CLI -> $i as bookalook_app" || bad "12 PHP CLI -> $i: $out"
done
echo "  phpredis (CLI): $(php -r 'echo phpversion("redis") ?: "not loaded";')"
# 13: PHP-FPM has the module (same binary and ini the running service uses)
/usr/sbin/php-fpm$PHPV -m 2>/dev/null | grep -qi '^redis$' && ok "13 php-fpm$PHPV loads the redis module" || bad "13 php-fpm$PHPV has no redis module"
# The RUNNING FPM (not just the binary): its master maps redis.so once it has
# been started or reloaded after the extension was installed.
FPM_PID=$(systemctl show -p MainPID --value php$PHPV-fpm)
if [ -n "$FPM_PID" ] && [ "$FPM_PID" != 0 ] && grep -q 'redis\.so' "/proc/$FPM_PID/maps" 2>/dev/null; then
  ok "13 running php$PHPV-fpm (pid $FPM_PID) has redis.so loaded"
else
  bad "13 running php$PHPV-fpm has not loaded redis.so yet — run: systemctl reload php$PHPV-fpm"
fi

echo; echo "===== Laravel untouched ====="
for d in /var/www/bookalook/backend /var/www/bookalook /var/www/*/backend; do [ -f "$d/artisan" ] && APP=$d && break; done
[ -n "${APP:-}" ] && grep -E '^(CACHE_STORE|QUEUE_CONNECTION|SESSION_DRIVER)=' "$APP/.env"

echo; echo "RESULT: $pass passed, $fail failed"
free -m
[ "$fail" -eq 0 ]
