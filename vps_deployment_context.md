# BookALook - VPS Deployment Context

This document contains the technical architecture and specifications for the **BookALook** project. It is intended to provide complete context to an AI assistant helping with the deployment of this project onto a newly purchased VPS.

## 1. VPS Specifications
- **Provider:** Hostinger
- **Resources:** 4 vCPU Cores, 16GB RAM, 200GB NVMe SSD
- **Recommended OS:** Ubuntu 22.04 LTS or 24.04 LTS

## 2. Project Architecture Overview
The project is split into multiple parts. For the VPS deployment, only the Backend and the Website (Frontend) need to be hosted. The mobile apps (Customer & Partner) will connect to the hosted backend via API.

1. **Backend (API):** Laravel 11.31 (PHP 8.2+)
2. **Frontend (Website):** Next.js 16.3.4 (React 19.2.8) with Node.js
3. **Database:** Currently configured for SQLite locally, but **must be migrated to MySQL/MariaDB or PostgreSQL** for production.
4. **Mobile Apps:** Flutter (Customer App, Partner App) — *These just need the backend API URL (HTTPS).*

## 3. Tech Stack Requirements on VPS
To successfully host this, the VPS needs the following installed:
- **Web Server:** Nginx (Recommended) or Apache2.
- **PHP:** PHP 8.2 or higher, along with `php-fpm` and common extensions (`mbstring`, `xml`, `bcmath`, `curl`, `mysql`, `sqlite3`, etc.).
- **Node.js:** Node.js v20+ and `npm`.
- **Process Manager:** PM2 (to keep Next.js running).
- **Database:** MySQL Server / MariaDB Server.
- **SSL Certificates:** Certbot (Let's Encrypt) is mandatory for HTTPS (required by Flutter apps and Razorpay).

---

## 4. Backend Setup Details (Laravel)
- **Directory:** `/backend`
- **Dependency Manager:** Composer

### Key Environment Variables (`.env`)
The backend relies on the following key services:
- **Database:** Needs `DB_CONNECTION`, `DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` configured for MySQL.
- **Cloudinary:** `CLOUDINARY_URL` (for image uploads).
- **Razorpay:** `RAZORPAY_DRIVER`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`.
- **WhatsApp Business:** `WHATSAPP_DRIVER`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_ACCESS_TOKEN`.
- **App URL:** `APP_URL` must point to the production API domain (e.g., `https://api.bookalook.com`).

### Deployment Steps (Reference for AI)
1. Navigate to `/backend`.
2. Run `composer install --optimize-autoloader --no-dev`.
3. Copy `.env.example` to `.env` and fill in production credentials.
4. Run `php artisan key:generate`.
5. Run `php artisan migrate --force`.
6. Run `php artisan storage:link`.
7. **Crucial:** Set ownership (`chown -R www-data:www-data storage bootstrap/cache`) and permissions (`chmod -R 775 storage bootstrap/cache`).
8. Configure Nginx to serve from `/backend/public` using PHP-FPM.

---

## 5. Frontend Setup Details (Next.js)
- **Directory:** `/website`
- **Dependency Manager:** npm

### Key Environment Variables (`.env`)
- `NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME`
- `NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET`
- *(Likely)* Needs an environment variable pointing to the backend API URL.

### Deployment Steps (Reference for AI)
1. Navigate to `/website`.
2. Run `npm install` (or `npm ci`).
3. Set up the production `.env` file.
4. Run `npm run build` to generate the production optimized bundle.
5. Start the server using PM2: `pm2 start npm --name "bookalook-web" -- start`.
6. Configure Nginx as a Reverse Proxy to route traffic from the main domain (e.g., `https://www.bookalook.com`) to `http://localhost:3000`.

---

## 6. Recommended Nginx Architecture
For a clean deployment, it's recommended to configure two separate Nginx server blocks (Virtual Hosts):
1. **Frontend Block:** Listens on `yourdomain.com`, terminates SSL, and proxy-passes to the PM2 Next.js process (Port 3000).
2. **Backend API Block:** Listens on `api.yourdomain.com`, terminates SSL, and serves the Laravel application via PHP-FPM.

*(Note for the AI: Make sure to assist the user in setting up firewall rules (UFW), securing the database, and configuring Let's Encrypt SSL certificates.)*
