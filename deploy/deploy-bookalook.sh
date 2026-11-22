#!/usr/bin/env bash
# Deploy BookALook on the production VPS:  bash /var/www/bookalook/deploy/deploy-bookalook.sh
#
# The routine that was run by hand, plus one step it was missing: reloading
# PHP-FPM. Production runs OPcache with validate_timestamps=0, so PHP never
# notices changed files; without a reload the API keeps serving the old code
# (from 2026-11-14 to 2026-11-22 every backend deploy reached only the queue
# workers, not the API the apps call).
#
# Stops at the first failure. Backs the database up before running migrations.
set -euo pipefail

APP=/var/www/bookalook
cd "$APP"

before=$(git rev-parse HEAD)
git pull --ff-only origin main
after=$(git rev-parse HEAD)
echo "Deployed: $(git log -1 --oneline)"

changed() { git diff --name-only "$before" "$after" -- "$@" | grep -q . ; }

# --- backend
cd "$APP/backend"
if changed backend/composer.lock; then
  composer install --no-dev --optimize-autoloader --no-interaction
fi
php artisan optimize:clear
if php artisan migrate:status --pending 2>/dev/null | grep -q "Pending"; then
  /usr/local/bin/bookalook-db-backup
fi
php artisan migrate --force
php artisan config:cache
php artisan view:cache
php artisan queue:restart

# The step that was missing: load the new code into the API.
systemctl reload php8.2-fpm
echo "PHP-FPM reloaded"

# --- website (only when it changed)
if changed website; then
  cd "$APP/website"
  if changed website/package-lock.json; then npm ci; fi
  npm run build
  pm2 restart bookalook-web
else
  echo "Website unchanged: not rebuilt"
fi

# --- checks
for url in https://bookalook.in https://bookalook.in/api/cities https://api.bookalook.in/api/cities; do
  printf '%-40s %s\n' "$url" "$(curl -sS -o /dev/null -w '%{http_code}' "$url")"
done
