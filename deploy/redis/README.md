# BookALook Redis — Phase 1 (infrastructure only)

Two Redis instances on the VPS. The Laravel app is **not** switched to them in
this phase: it keeps `CACHE_STORE=database` and `QUEUE_CONNECTION=database`.

| Instance | Unit | Port | Memory | Policy | Persistence |
| --- | --- | --- | --- | --- | --- |
| cache | `bookalook-redis@cache` | 6379 | 512 MB | `allkeys-lru` | none |
| state | `bookalook-redis@state` | 6380 | 256 MB | `noeviction` | AOF `everysec` + RDB |

Both bind to `127.0.0.1` and `::1` only. Users per instance: `default` (off),
`bookalook_app` (no FLUSHALL/FLUSHDB/CONFIG/DEBUG/SHUTDOWN/ACL/…),
`bookalook_admin` (operations only). Passwords are generated on the server into
`/etc/bookalook-redis/secrets/` (root, 0600); the ACL files hold only SHA-256 hashes.
Nothing secret is in this repository.

## Run order (as root on the VPS)

```bash
sudo bash 00-inspect.sh 2>&1 | tee /tmp/bookalook-redis-inspect.txt   # read-only
sudo FLAVOR=valkey PHPV=8.2 bash 10-install.sh                       # asks at gates A, B, C
sudo FLAVOR=valkey PHPV=8.2 bash 30-verify.sh
```

`FLAVOR` is `valkey` or `redis`, picked from what `00-inspect.sh` shows apt offers.

Rollback: `sudo FLAVOR=valkey PHPV=8.2 bash 90-rollback.sh` (moves data aside, never deletes it).

## Where things go on the server

| Path | What |
| --- | --- |
| `/etc/bookalook-redis/{cache,state}/redis.conf` | instance config |
| `/etc/bookalook-redis/{cache,state}/users.acl` | ACL users (hashes) |
| `/etc/bookalook-redis/secrets/*.pass` | passwords, root only |
| `/var/lib/bookalook-redis/{cache,state}` | data (state: AOF + RDB) |
| `/var/log/bookalook-redis/{cache,state}.log` | logs |
| `/etc/systemd/system/bookalook-redis@.service` | systemd template |
| `/etc/sysctl.d/60-bookalook-redis.conf` | `vm.overcommit_memory = 1` |
