# Phase 4 cutover — database queue to Redis queue

Run on the VPS as root, one step at a time, and check each result before the
next. Nothing here deletes a job, flushes Redis or touches business data.

The idea: the existing database worker keeps running (and is told to read
every queue name explicitly from the `database` connection) until the old
`jobs` table is empty — including campaign jobs delayed into the future —
while new jobs go to Redis and are run by the new workers. Nothing is ever
stranded, and both can run side by side safely because every job re-checks
its PostgreSQL row before acting.

## A. Read-only checks (send me the output before step B)

```bash
systemctl cat bookalook-queue --no-pager
```

```bash
cd /var/www/bookalook/backend && php artisan tinker --execute="echo json_encode(['jobs_by_queue'=>DB::table('jobs')->selectRaw('queue, count(*) as n, sum(case when reserved_at is not null then 1 else 0 end) as reserved, sum(case when available_at > extract(epoch from now()) then 1 else 0 end) as delayed')->groupBy('queue')->get(), 'failed_jobs'=>DB::table('failed_jobs')->count(), 'whatsapp_queued'=>DB::table('whatsapp_messages')->where('status','queued')->count(), 'push_pending'=>DB::table('notification_deliveries')->where('status','pending')->count(), 'campaigns_scheduled'=>DB::table('campaigns')->where('status','scheduled')->count(), 'campaigns_sending'=>DB::table('campaigns')->where('status','sending')->count()], JSON_PRETTY_PRINT);"
```

```bash
ps -o pid,rss,etime,args -C php | grep -E '[q]ueue:work'; free -m
```

## B. Deploy the code (queue still on the database)

Adds 3 columns and a small index to `notifications` (instant column add, index
built CONCURRENTLY — no write lock). Widens the existing database worker to
the new queue names so nothing waits unprocessed.

```bash
cd /var/www/bookalook && git pull origin main && cd backend && php artisan migrate --force && php artisan config:cache
```

```bash
sudo mkdir -p /etc/systemd/system/bookalook-queue.service.d && printf '[Service]\nExecStart=\nExecStart=/usr/bin/php artisan queue:work database --queue=critical,notifications,marketing,default --sleep=3 --tries=3 --timeout=120\nTimeoutStopSec=150\n' | sudo tee /etc/systemd/system/bookalook-queue.service.d/queues.conf && sudo systemctl daemon-reload && sudo systemctl restart bookalook-queue && systemctl status bookalook-queue --no-pager | head -6
```

(If step A shows the unit has no `WorkingDirectory=/var/www/bookalook/backend`, stop and tell me first.)

Check the recovery sweep sees nothing odd:

```bash
cd /var/www/bookalook/backend && php artisan app:recover-queued-work --dry-run
```

Then use the apps normally for a while (a login, a booking): everything still
runs through the database queue, now with the new safety checks.

## C. Install the Redis workers (not started yet)

```bash
sudo mkdir -p /etc/bookalook-workers /var/log/bookalook-workers && sudo chown www-data:www-data /var/log/bookalook-workers && echo 'QUEUES=critical' | sudo tee /etc/bookalook-workers/critical-1.env && echo 'QUEUES=critical,notifications,default' | sudo tee /etc/bookalook-workers/notifications-1.env /etc/bookalook-workers/notifications-2.env && echo 'QUEUES=marketing' | sudo tee /etc/bookalook-workers/marketing-1.env && sudo cp /var/www/bookalook/deploy/queue/bookalook-worker@.service /etc/systemd/system/ && sudo systemctl daemon-reload && systemctl list-unit-files 'bookalook-worker@*' --no-pager
```

## D. Cutover (needs your explicit go-ahead)

1. Switch new dispatches to Redis and start the Redis workers:

```bash
cd /var/www/bookalook/backend && cp .env /root/env-before-queue-$(date +%Y%m%d-%H%M%S) && sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/' .env && php artisan config:cache && sudo systemctl enable --now bookalook-worker@critical-1 bookalook-worker@notifications-1 bookalook-worker@notifications-2 bookalook-worker@marketing-1 && grep -E '^(QUEUE_CONNECTION|CACHE_STORE)=' .env
```

2. Check the workers are up and the Redis queues are being read:

```bash
systemctl is-active bookalook-worker@critical-1 bookalook-worker@notifications-1 bookalook-worker@notifications-2 bookalook-worker@marketing-1 bookalook-queue; cd /var/www/bookalook/backend && php artisan queue:monitor redis:critical,redis:notifications,redis:marketing,database:default
```

3. Log in once on the Customer App (WhatsApp code goes through `critical`),
   then:

```bash
tail -n 5 /var/log/bookalook-workers/critical-1.log /var/log/bookalook-workers/notifications-1.log; cd /var/www/bookalook/backend && php artisan tinker --execute="App\Models\WhatsAppMessage::where('category','authentication')->latest()->take(1)->get(['status','created_at'])->each(fn(\$m)=>print(\$m->created_at.' '.\$m->status.PHP_EOL));"
```

4. Watch the old table drain (repeat until `pending_now` is 0):

```bash
cd /var/www/bookalook/backend && php artisan tinker --execute="echo json_encode(['pending_now'=>DB::table('jobs')->where('available_at','<=',time())->count(), 'delayed_future'=>DB::table('jobs')->where('available_at','>',time())->count(), 'reserved'=>DB::table('jobs')->whereNotNull('reserved_at')->count()]);"
```

5. When `pending_now`, `reserved` and `delayed_future` are all 0, retire the
   database worker (it finishes its current job first):

```bash
sudo systemctl disable --now bookalook-queue && systemctl is-active bookalook-queue
```

   If `delayed_future` stays above 0 (a campaign scheduled days ahead), leave
   the database worker running until then — it costs one idle process.

6. Measure worker memory after an hour of normal traffic:

```bash
ps -o pid,rss,etime,args -C php | grep -E '[q]ueue:work'; sudo env VALKEYCLI_AUTH="$(sudo cat /etc/bookalook-redis/secrets/state-admin.pass)" valkey-cli --no-auth-warning -p 6380 --user bookalook_admin INFO memory | grep -E 'used_memory_human|maxmemory_human'
```

## Rollback (any time)

New jobs back to the database queue; Redis workers finish what they hold.

```bash
cd /var/www/bookalook/backend && sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=database/' .env && php artisan config:cache && sudo systemctl enable --now bookalook-queue && sudo -u www-data php artisan queue:work redis --queue=critical,notifications,marketing,default --stop-when-empty && sudo systemctl disable --now bookalook-worker@critical-1 bookalook-worker@notifications-1 bookalook-worker@notifications-2 bookalook-worker@marketing-1
```

The `--stop-when-empty` run drains anything left in Redis (delayed jobs
excepted — the recovery sweep re-queues their work from PostgreSQL).
Code rollback: the new columns are additive and harmless; `php artisan migrate:rollback --step=1` removes them if ever needed.

## What to watch afterwards

- `storage/logs/laravel.log`: `queue.dispatch_failed`, `queue.push_given_up`,
  `queue.whatsapp_outcome_unknown`, `queue.recovered`.
- `failed_jobs` (PostgreSQL): `php artisan queue:failed`; retry one with
  `php artisan queue:retry <id>` — safe: every job re-checks its row first.
- WhatsApp rows failed with "Outcome unknown": may or may not have arrived;
  resend deliberately with `php artisan app:resend-whatsapp`.
