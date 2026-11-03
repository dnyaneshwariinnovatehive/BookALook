# Phase 2 + 3 deploy — Laravel on Redis (cache + state)

Run on the VPS as root, in order. Each step says what it changes.
`QUEUE_CONNECTION=database` is never touched.

## 0. Before anything (blocking)

- WhatsApp OTP must be switched ON in SuperAdmin and tested with a real phone.
  This deploy includes Phase 0: production no longer has a demo code, so with
  WhatsApp OTP off nobody could log in.
- Find out what restarts the queue worker (it must come back after step 6):

```bash
ps -o pid,ppid,user,etime,args -C php | grep -E '[q]ueue:work'
```

```bash
ps -o pid,args -p "$(ps -o ppid= -p "$(pgrep -f 'artisan queue:work' | head -1)")"
```

  If the parent is `systemd`/`supervisord`/`pm2`, it will be restarted. If it is
  a shell or `nohup`, tell me before continuing.

## 1. Back up and pull

```bash
cd /var/www/bookalook/backend && cp .env /root/env-backup-$(date +%Y%m%d-%H%M%S)
```

```bash
cd /var/www/bookalook && git pull origin main
```

## 2. Let the app user FLUSHDB on the cache instance only (for optimize:clear)

Changes the ACL of 6379 only; 6380 is untouched. No restart (ACL LOAD).

```bash
sudo cp /etc/bookalook-redis/cache/users.acl /root/cache-users.acl.bak && sudo sed -i '/^user bookalook_app /s/ -flushdb//' /etc/bookalook-redis/cache/users.acl && sudo env VALKEYCLI_AUTH="$(sudo cat /etc/bookalook-redis/secrets/cache-admin.pass)" valkey-cli --no-auth-warning -p 6379 --user bookalook_admin ACL LOAD
```

## 3. Add the Redis credentials to .env (values are read from the secrets files, never printed)

```bash
cd /var/www/bookalook/backend && { echo; echo "# Redis (Phase 2) - see deploy/redis"; echo "REDIS_CACHE_USERNAME=bookalook_app"; echo "REDIS_CACHE_PASSWORD=$(sudo cat /etc/bookalook-redis/secrets/cache-app.pass)"; echo "REDIS_STATE_USERNAME=bookalook_app"; echo "REDIS_STATE_PASSWORD=$(sudo cat /etc/bookalook-redis/secrets/state-app.pass)"; } >> .env && grep -c '^REDIS_\(CACHE\|STATE\)_' .env
```

(Expect `4`. `CACHE_STORE` is still `database` at this point.)

## 4. Load config and run the self-check against the real instances

From here OTP codes and rate limits are on the state instance (6380).
Codes sent in the last 10 minutes before this step are gone — people ask again.

```bash
cd /var/www/bookalook/backend && php artisan optimize:clear && php artisan config:cache && php artisan app:redis-selfcheck
```

Must end with `RESULT: N passed, 0 failed`. If not: stop and send me the output
(rollback below).

## 5. Switch the app cache to Redis

```bash
cd /var/www/bookalook/backend && sed -i 's/^CACHE_STORE=.*/CACHE_STORE=redis/' .env && php artisan config:cache && php artisan view:cache && grep -E '^(CACHE_STORE|QUEUE_CONNECTION)=' .env
```

## 6. Restart the queue worker so it loads the new config

The running worker still reads its restart signal from the DATABASE cache, so
the signal is written there too.

```bash
cd /var/www/bookalook/backend && php artisan queue:restart && php artisan tinker --execute="Cache::store('database')->forever('illuminate:queue:restart', now()->getTimestamp()); echo 'signalled';"
```

```bash
sleep 10; ps -o pid,etime,args -C php | grep -E '[q]ueue:work'
```

(The worker's elapsed time should now be seconds, not days.)

## 7. Smoke test

```bash
for u in https://api.bookalook.in/api/cities https://api.bookalook.in/api/customer/categories https://api.bookalook.in/api/app-version/customer https://api.bookalook.in/api/public/subscription-plans; do curl -sS -o /dev/null -w "%{http_code} %{time_total}s $u\n" "$u"; done
```

```bash
tail -n 50 /var/www/bookalook/backend/storage/logs/laravel.log | grep -iE 'redis|app_cache' || echo "no redis errors in the log"
```

Then log in once on each app with a real WhatsApp code, and once on SuperAdmin.

## Rollback (no code change, no data loss)

App cache back to PostgreSQL:

```bash
cd /var/www/bookalook/backend && sed -i 's/^CACHE_STORE=.*/CACHE_STORE=database/' .env && php artisan config:cache && php artisan queue:restart
```

OTP codes and rate limits back to PostgreSQL as well:

```bash
cd /var/www/bookalook/backend && (grep -q '^STATE_STORE_DRIVER=' .env && sed -i 's/^STATE_STORE_DRIVER=.*/STATE_STORE_DRIVER=database/' .env || echo 'STATE_STORE_DRIVER=database' >> .env) && php artisan config:cache
```

Full code rollback: restore the .env backup from step 1, `git checkout` the
previous commit, `php artisan config:cache`, `php artisan queue:restart`.
FLUSHDB ACL: `sudo cp /root/cache-users.acl.bak /etc/bookalook-redis/cache/users.acl` then the ACL LOAD command from step 2.
