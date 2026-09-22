# PostgreSQL 18 Migration Audit Report

This is a read-only audit of the BookALook Laravel 11 backend, assessing its readiness for migrating from SQLite to PostgreSQL 18 in production.

## A. PHP/Laravel requirements
- **PHP Version:** `^8.2` (Required by `composer.json`).
- **Laravel Version:** `^11.31` (Required by `composer.json`).
- **Database Packages:** No specific PostgreSQL DBAL packages are installed, but Laravel 11 uses PHP's native `pdo_pgsql` extension. You must ensure the `php8.2-pgsql` (or equivalent) extension is installed on the VPS.

## B. Database configuration
- **Config File:** `config/database.php` configures the default connection via `env('DB_CONNECTION', 'sqlite')`.
- **Connections Defined:** `sqlite`, `mysql`, `mariadb`, `pgsql`, `sqlsrv`.
- **PostgreSQL Settings:** The `pgsql` driver is correctly defined in `config/database.php` (lines 85-98) and expects connections on port `5432` with a `utf8` charset and `public` search path.
- **Queue/Cache/Session:** By default, these rely on the database. In `config/queue.php`, the database connection explicitly falls back to `env('DB_CONNECTION', 'sqlite')`.

## C. SQLite-specific code
Several parts of the application have branches specifically for SQLite because it lacks built-in features (like trigonometry):
- `app/Providers/AppServiceProvider.php` (Line 81-91): Injects a custom `haversine_km` function directly into the SQLite PDO connection.
- `app/Services/GeoService.php` (Line 75): Checks if `$driver === 'sqlite'` to use the custom `haversine_km` function.
- `app/Services/Marketing/AudienceBuilder.php` (Line 249): Checks if `$driver === 'sqlite'` to format dates using `strftime('%m-%d', u.date_of_birth)`.
- `composer.json` (Line 49): Has a post-create-project script that blindly touches `database/database.sqlite`.

## D. PostgreSQL compatibility issues
🚨 **CRITICAL ISSUES DETECTED:**
1. **Raw SQL Functions (`AudienceBuilder.php`)**: The audience builder falls back to MySQL's `DATE_FORMAT(u.date_of_birth, '%m-%d')` if the driver is not `sqlite`. PostgreSQL does **not** support `DATE_FORMAT()`; it uses `TO_CHAR(date, 'MM-DD')`. This will crash when generating birthday segments on PostgreSQL.
2. **UUID Generation (`2026_09_02_000034_create_salon_enquiries_table.php`)**: The migration uses `->default(DB::raw('(UUID())'))`. The `UUID()` function is MySQL-specific. PostgreSQL requires `gen_random_uuid()` or `uuid_generate_v4()`. This migration will fail immediately.
3. **Double Quoted Strings/Raw Queries**: Throughout `SuperAdminCustomerController.php` and `PlatformReportController.php`, complex `selectRaw()` queries are used (e.g. `selectRaw('date(created_at) as d')`). PostgreSQL is stricter about `GROUP BY` clauses and aliases than SQLite/MySQL. Any `selectRaw` omitting grouped columns may trigger `SQLSTATE[42803]: Grouping error`.

## E. Migration risks
- **Missing Foreign Keys:** `2026_09_12_000000_link_salons_to_the_enquiry_they_came_from.php` deliberately omits a foreign key with the comment "No foreign key — SQLite cannot add one to an existing table". In PostgreSQL, you can and should add this foreign key constraint.
- **Data Type Casting:** SQLite ignores column lengths (e.g., `string('phone', 15)`). PostgreSQL enforces them strictly. Ensure no existing seeders or code insert strings longer than the specified length.
- **Update with Join/Subquery:** `2026_09_16_100000_give_reviews_and_complaints_a_clock_and_an_outcome.php` runs a `DB::statement` to update `reviews`. The syntax used is standard and should execute successfully on PostgreSQL, but should be tested.
- **Enums & JSON:** Migrations extensively use `->enum()` and `->json()`/`->jsonb()`. PostgreSQL natively supports JSONB and Enums. However, modifying Enum columns in the future requires `doctrine/dbal` and raw `ALTER TYPE` statements in Postgres.

## F. Required production environment variables
*No secret values are shown here.*
- **Database:** `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`
- **Application:** `APP_NAME`, `APP_ENV`, `APP_KEY`, `APP_DEBUG`, `APP_URL`, `FRONTEND_URL`
- **External Services:** 
  - `CLOUDINARY_URL`
  - `RAZORPAY_DRIVER`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`
  - `WHATSAPP_DRIVER`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_ACCESS_TOKEN`

## G. Queues/scheduler/cache/session requirements
- **Session:** `SESSION_DRIVER=database`
- **Queue:** `QUEUE_CONNECTION=database`
- **Cache:** `CACHE_STORE=database`
- **Implication:** PostgreSQL will handle sessions, queues, and cache. You must ensure `php artisan queue:work` is running via PM2 or Supervisor to process background jobs (like WhatsApp notifications).

## H. Storage/file-upload requirements
- **Driver:** `FILESYSTEM_DISK=local` is the default, but `Cloudinary` is actively used for media.
- **Local Storage:** You will need to run `php artisan storage:link` during deployment so that any locally saved avatars or exports are accessible from the `public/` directory. Directory permissions for `storage/` and `bootstrap/cache/` must be `775` and owned by `www-data`.

## I. Authentication/CORS requirements
- **Authentication:** `laravel/sanctum` is used (`composer.json`). API routes require token-based authentication.
- **CORS:** Ensure `config/cors.php` allows the production Next.js frontend domain (and mobile app origins if applicable) to avoid preflight request failures.

## J. Git/secret-safety issues
- ⚠️ **Git Tracking Vulnerability:** Running `git ls-files` reveals that `database/database.sqlite` and `storage/dev/database.backup.sqlite` are **currently tracked by Git**. This is a major security risk. If pushed to a public repository, actual user data could be exposed.
- **Secrets:** `.env` is safely ignored. Only `.env.example` is tracked.

## K. Exact recommended changes before PostgreSQL migration

1. **Fix `AudienceBuilder.php` (Line 249):**
   Update the database driver logic to handle PostgreSQL correctly:
   ```php
   $monthDay = match($driver) {
       'sqlite' => "strftime('%m-%d', u.date_of_birth)",
       'pgsql' => "TO_CHAR(u.date_of_birth, 'MM-DD')",
       default => "DATE_FORMAT(u.date_of_birth, '%m-%d')"
   };
   ```

2. **Fix `2026_09_02_000034_create_salon_enquiries_table.php` (Line 13):**
   Change the MySQL specific UUID function to Laravel's framework-agnostic helper, or use the Postgres equivalent:
   ```php
   // Recommended Laravel approach (avoids DB raw entirely):
   $table->uuid('id')->primary();
   // Or if default is strictly required at DB level:
   $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()')); 
   ```

3. **Untrack SQLite files:**
   Run `git rm --cached database/database.sqlite` and `git rm --cached storage/dev/database.backup.sqlite`, then commit, to stop tracking local databases.

4. **Verify Group By Clauses:** 
   Review all `selectRaw` queries in `SuperAdminCustomerController.php` and `PlatformReportController.php` against PostgreSQL `strict` mode to ensure all non-aggregated columns in SELECT are also in GROUP BY.

## L. Commands that should be run during deployment
```bash
# 1. Install dependencies
composer install --optimize-autoloader --no-dev

# 2. Setup environment (ensure DB_CONNECTION=pgsql in .env)
cp .env.example .env
php artisan key:generate

# 3. Create storage links and set permissions
php artisan storage:link
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# 4. Migrate database
php artisan migrate --force

# 5. Start Queue worker
php artisan queue:restart
# (Configure Supervisor or PM2 to run `php artisan queue:work --tries=3`)
```
