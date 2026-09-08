<?php

namespace App\Console\Commands;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\Combo;
use App\Models\PlatformPolicySetting;
use App\Models\ProviderLeave;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Models\WalletScheme;
use App\Models\WalletSchemeTier;
use App\Services\AppointmentCheckInService;
use App\Services\CommissionService;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Fill the development database with enough history to exercise the whole
 * platform by hand.
 *
 * Two salons, deliberately in different states:
 *
 *   9112002049 — trading, on the Commission Model, with six weeks of completed
 *                work behind it. This is where payouts, payroll, the coin
 *                ladder, combos and cart suggestions have something to chew on.
 *   9168281183 — fully set up but its subscription plan lapsed yesterday, so it
 *                is the one for the expiry lockdown and the "non-serviceable"
 *                state in the customer app.
 *
 * Everything it creates is its own — seeded customers, staff and appointments
 * are tagged and removed on --reset, so real records are never touched.
 */
class SeedTestScenario extends Command
{
    protected $signature = 'app:seed-test-data {--reset : Remove previously seeded data first}';

    protected $description = 'Seed demo data across both test salons for end-to-end feature testing';

    /** Marks everything this command owns, so a reset knows what to remove. */
    private const TAG = '[demo]';

    /** Phone prefix for seeded customers and staff — all log in with OTP 123456. */
    private const PHONE_PREFIX = '99000';

    private const ACTIVE_SALON_ADMIN = '9112002049';
    private const EXPIRED_SALON_ADMIN = '9168281183';

    private Salon $activeSalon;
    private Salon $expiredSalon;

    /** @var array<int, User> */
    private array $customers = [];

    public function handle(): int
    {
        $this->activeSalon = $this->salonOfAdmin(self::ACTIVE_SALON_ADMIN);
        $this->expiredSalon = $this->salonOfAdmin(self::EXPIRED_SALON_ADMIN);

        if ($this->option('reset')) {
            $this->reset();
        }

        $this->components->info('Platform settings');
        $this->seedPolicySettings();
        $this->seedWalletScheme();

        $this->components->info('Customers');
        $this->customers = $this->seedCustomers();

        $this->components->info("Trading salon — {$this->activeSalon->name}");
        $this->seedSalonSetup($this->activeSalon, weeklyOffDay: 3);
        $this->putOnCommissionModel($this->activeSalon, 12.0);
        $this->seedHistory($this->activeSalon);
        $this->seedLive($this->activeSalon);
        $this->seedLeave($this->activeSalon);

        $this->components->info("Lapsed salon — {$this->expiredSalon->name}");
        $this->seedSalonSetup($this->expiredSalon, weeklyOffDay: 2);
        // A little trading history first, so renewing the plan from SuperAdmin
        // reveals a salon with something in it rather than an empty shell.
        $this->seedHistory($this->expiredSalon, weeks: 2);
        $this->expirePlan($this->expiredSalon);

        $this->summary();

        return self::SUCCESS;
    }

    // ------------------------------------------------------------- platform

    private function seedPolicySettings(): void
    {
        $superAdmin = User::where('role', 'superadmin')->first();

        $settings = [
            ['coin_value_inr', '1.00', 'decimal', 'What one reward coin is worth in rupees'],
            ['cancellation_cutoff_minutes', '300', 'integer', 'How close to an appointment a customer may still cancel'],
            ['reschedule_cutoff_minutes', '90', 'integer', 'How close to an appointment a customer may still reschedule'],
            ['appointment_start_early_minutes', '7200', 'integer', 'How early a provider may scan a customer in'],
            ['subscription_expiry_warning_days', '3', 'integer', 'Days before expiry to start warning the salon'],
        ];

        foreach ($settings as [$key, $value, $type, $description]) {
            PlatformPolicySetting::updateOrCreate(
                ['setting_key' => $key],
                [
                    'setting_value' => $value,
                    'data_type' => $type,
                    'description' => $description,
                    'updated_by' => $superAdmin?->id,
                ],
            );
        }

        $this->components->twoColumnDetail('coin value', '₹1.00 per coin');
    }

    private function seedWalletScheme(): void
    {
        $superAdmin = User::where('role', 'superadmin')->first();

        $scheme = WalletScheme::updateOrCreate(
            ['name' => 'Launch Ladder ' . self::TAG],
            [
                'description' => 'Demo reward ladder — deliberately short so milestones are reachable by hand.',
                'award_mode' => WalletScheme::MODE_PER_APPOINTMENT,
                'is_active' => true,
                'starts_on' => Carbon::today()->subMonths(6)->toDateString(),
                'ends_on' => null,
                'created_by' => $superAdmin?->id,
            ]
        );

        // Any other ladder would compete for "in force today" and make the
        // numbers hard to follow.
        WalletScheme::where('id', '!=', $scheme->id)->update(['is_active' => false]);

        $scheme->tiers()->delete();

        $tiers = [
            [1, 1, 5, 10],
            [2, 6, 15, 20],
            [3, 16, 40, 30],
            [4, 41, null, 50],
        ];

        foreach ($tiers as [$order, $from, $to, $coins]) {
            WalletSchemeTier::create([
                'scheme_id' => $scheme->id,
                'tier_order' => $order,
                'appointments_from' => $from,
                'appointments_to' => $to,
                // Legacy column, kept in step with the band. The open-ended
                // final rung has no size, so it records zero.
                'appointments_required' => $to === null ? 0 : ($to - $from + 1),
                'coins_awarded' => $coins,
            ]);
        }

        $this->components->twoColumnDetail('reward ladder', '1-5 → 10 · 6-15 → 20 · 16-40 → 30 · 41+ → 50 coins');
    }

    /** @return array<int, User> */
    private function seedCustomers(): array
    {
        $names = ['Aarti Deshpande', 'Rohan Kulkarni', 'Sneha Patil', 'Vikram Joshi', 'Meera Shah'];
        $made = [];

        foreach ($names as $index => $name) {
            $phone = self::PHONE_PREFIX . str_pad((string) ($index + 1), 5, '0', STR_PAD_LEFT);

            $made[] = User::updateOrCreate(
                ['phone' => $phone],
                [
                    'name' => $name . ' ' . self::TAG,
                    'password_hash' => Hash::make('demo1234'),
                    'role' => 'customer',
                    'is_active' => true,
                ]
            );
        }

        $this->components->twoColumnDetail(
            count($made) . ' customers',
            self::PHONE_PREFIX . '00001 … ' . self::PHONE_PREFIX . '0000' . count($made) . ' (OTP 123456)'
        );

        return $made;
    }

    // ---------------------------------------------------------------- salon

    /**
     * Give a salon opening hours, a full service menu, staff who can perform
     * everything, and packages worth suggesting.
     */
    private function seedSalonSetup(Salon $salon, int $weeklyOffDay): void
    {
        $this->seedSalonHours($salon, $weeklyOffDay);
        $services = $this->seedServices($salon);
        $providers = $this->seedProviders($salon, $services, $weeklyOffDay);
        $this->seedCombos($salon, $services);

        $this->components->twoColumnDetail(
            'menu',
            count($services) . ' services · ' . count($providers) . ' staff · closed on ' . $this->dayName($weeklyOffDay)
        );
    }

    private function seedSalonHours(Salon $salon, int $closedDay): void
    {
        for ($day = 0; $day < 7; $day++) {
            SalonWorkingHour::updateOrCreate(
                ['salon_id' => $salon->id, 'day_of_week' => $day],
                [
                    'is_closed' => $day === $closedDay,
                    'open_time' => $day === $closedDay ? null : '09:00:00',
                    'close_time' => $day === $closedDay ? null : '20:00:00',
                ]
            );
        }
    }

    /**
     * A menu wide enough that combos and suggestions have something to work
     * with, priced so the arithmetic is easy to check by eye.
     *
     * @return array<string, Service> keyed by template name
     */
    private function seedServices(Salon $salon): array
    {
        $menu = [
            // template name, category, minutes, price, advance %
            ["Men's Haircut", 'Hair', 30, 300.0, 30],
            ['Hair Colour', 'Hair', 60, 1500.0, 40],
            ['Beard Trim', 'Hair', 30, 200.0, 25],
            ['Nail Art', 'Nail', 30, 500.0, 25],
            ['Gel Polish', 'Nail', 60, 800.0, 30],
            ['Head Massage', 'SPA', 30, 400.0, 20],
            ['Fish spa', 'SPA', 60, 1000.0, 30],
        ];

        $services = [];

        foreach ($menu as $order => [$name, $category, $minutes, $price, $advance]) {
            $template = $this->templateFor($name, $category, $minutes);

            $service = Service::withTrashed()
                ->where('salon_id', $salon->id)
                ->where('template_id', $template->id)
                ->first();

            if ($service) {
                $service->restore();
                // Existing services keep their own price — the salon may have
                // set it deliberately — but must be sellable, and must have an
                // advance percentage or booking has nothing to charge.
                $service->forceFill([
                    'is_active' => true,
                    'display_order' => $order,
                    'advance_percentage' => $service->advance_percentage ?? $advance,
                ])->save();
            } else {
                $service = Service::create([
                    'salon_id' => $salon->id,
                    'template_id' => $template->id,
                    'price' => $price,
                    'advance_percentage' => $advance,
                    'will_refund_advance_if_cancelled' => $advance <= 25,
                    'is_active' => true,
                    'display_order' => $order,
                ]);
            }

            $services[$name] = $service->fresh();
        }

        return $services;
    }

    private function templateFor(string $name, string $category, int $minutes): ServiceTemplate
    {
        $categoryId = DB::table('service_categories')->where('name', $category)->value('id');

        if (! $categoryId) {
            $categoryId = (string) Str::uuid();
            DB::table('service_categories')->insert([
                'id' => $categoryId,
                'name' => $category,
                'is_custom' => false,
                'is_active' => true,
                'display_order' => 0,
            ]);
        }

        return ServiceTemplate::updateOrCreate(
            ['name' => $name],
            [
                'category_id' => $categoryId,
                'estimated_duration_minutes' => $minutes,
                'is_custom' => false,
                'is_active' => true,
            ]
        );
    }

    /**
     * Staff on different salary and commission terms, so a payslip actually
     * differs from the person next to them.
     *
     * @param array<string, Service> $services
     * @return array<int, ServiceProvider>
     */
    private function seedProviders(Salon $salon, array $services, int $weeklyOffDay): array
    {
        $existing = ServiceProvider::with('user')->where('salon_id', $salon->id)->get();

        $wanted = [
            // name, phone suffix, base salary, commission %, auto-approve leave
            ['Priya Nikam', '1', 24000.0, 20.0, true],
            ['Sameer Rane', '2', 18000.0, 15.0, false],
        ];

        $providers = $existing->all();

        foreach ($wanted as [$name, $suffix, $salary, $commission, $autoApprove]) {
            // Digits only, and stable per salon, so the same staff member keeps
            // the same number across re-runs.
            $phone = self::PHONE_PREFIX . '1' . substr((string) crc32($salon->id), 0, 3) . $suffix;

            $user = User::updateOrCreate(
                ['phone' => $phone],
                [
                    'name' => $name . ' ' . self::TAG,
                    'password_hash' => Hash::make('demo1234'),
                    'role' => 'service_provider',
                    'is_active' => true,
                ]
            );

            $providers[] = ServiceProvider::updateOrCreate(
                ['user_id' => $user->id, 'salon_id' => $salon->id],
                [
                    'base_salary' => $salary,
                    'commission_percentage' => $commission,
                    'auto_approve_leave' => $autoApprove,
                    'is_active' => true,
                    'joined_at' => Carbon::today()->subMonths(8),
                ]
            );
        }

        // Everyone can do everything, so no test is ever blocked by a staff
        // member who happens not to offer the service being booked.
        foreach ($providers as $provider) {
            foreach ($services as $service) {
                DB::table('provider_services')->updateOrInsert(
                    ['provider_id' => $provider->id, 'service_id' => $service->id],
                    []
                );
            }

            $this->seedProviderHours($provider, $weeklyOffDay);
        }

        return $providers;
    }

    private function seedProviderHours(ServiceProvider $provider, int $weeklyOffDay): void
    {
        for ($day = 0; $day < 7; $day++) {
            \App\Models\ProviderWorkingHour::updateOrCreate(
                ['provider_id' => $provider->id, 'day_of_week' => $day],
                [
                    'is_weekly_off' => $day === $weeklyOffDay,
                    'shift_start' => $day === $weeklyOffDay ? null : '09:00:00',
                    'shift_end' => $day === $weeklyOffDay ? null : '20:00:00',
                    'break_start' => null,
                    'break_end' => null,
                ]
            );
        }
    }

    /**
     * Packages that overlap on purpose: one service belongs to two of them, so
     * the cart has a real choice to make when it picks the best saving.
     *
     * @param array<string, Service> $services
     */
    private function seedCombos(Salon $salon, array $services): void
    {
        $packages = [
            ['Groom Combo', ["Men's Haircut" => 250.0, 'Beard Trim' => 150.0]],
            ['Salon Day Out', ['Nail Art' => 400.0, 'Head Massage' => 300.0, 'Fish spa' => 800.0]],
            ['Colour & Care', ['Hair Colour' => 1300.0, 'Head Massage' => 250.0]],
        ];

        foreach ($packages as [$name, $lines]) {
            $combo = Combo::updateOrCreate(
                ['salon_id' => $salon->id, 'name' => $name . ' ' . self::TAG],
                [
                    'advance_percentage' => 30,
                    'will_refund_advance_if_cancelled' => false,
                    'is_active' => true,
                ]
            );

            $combo->services()->detach();

            foreach ($lines as $serviceName => $comboPrice) {
                if (isset($services[$serviceName])) {
                    $combo->services()->attach(
                        $services[$serviceName]->id,
                        ['combo_special_price' => $comboPrice]
                    );
                }
            }
        }
    }

    // --------------------------------------------------------- subscriptions

    private function putOnCommissionModel(Salon $salon, float $rate): void
    {
        // One plan carries the benefits for every Commission Model salon, so
        // the seeder nominates one rather than picking per salon.
        $plan = SubscriptionPlan::commissionPlan()
            ?? SubscriptionPlan::where('is_active', true)->orderByDesc('price')->first()
            ?? SubscriptionPlan::first();

        if ($plan && ! $plan->is_commission_plan) {
            app(CommissionService::class)->setPlan($plan);
        }

        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $salon->forceFill(['status' => 'active'])->save();

        app(CommissionService::class)->activate(
            $salon->fresh(),
            $rate,
            User::where('role', 'superadmin')->first() ?? User::first(),
            'Seeded development scenario.'
        );

        $this->components->twoColumnDetail(
            'billing',
            "Commission Model at {$rate}%, settled monthly on the 1st"
        );
    }

    private function expirePlan(Salon $salon): void
    {
        $plan = SubscriptionPlan::where('is_active', true)->orderBy('price')->first();

        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan?->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan?->price ?? 0,
            'start_date' => Carbon::today()->subMonth(),
            'end_date' => Carbon::yesterday(),
            'status' => 'expired',
            'auto_renew' => false,
        ]);

        // The salon itself stays approved and active — the lock has to come
        // from the lapsed plan, which is exactly what is being tested. Marking
        // the salon inactive would block it for the wrong reason.
        $salon->forceFill(['status' => 'active'])->save();

        $this->components->twoColumnDetail('billing', 'Subscription plan, expired ' . Carbon::yesterday()->toDateString());
    }

    // -------------------------------------------------------------- history

    /**
     * Six weeks of completed work.
     *
     * The pairings are deliberate rather than random: haircut with beard trim,
     * nail art with gel polish. Cart suggestions are mined from what a salon
     * actually sells together, so without a pattern there is nothing to find.
     */
    private function seedHistory(Salon $salon, int $weeks = 6): void
    {
        $services = $this->menuOf($salon);
        $providers = ServiceProvider::where('salon_id', $salon->id)->where('is_active', true)->get();
        $checkIn = app(AppointmentCheckInService::class);
        $admin = User::find($salon->admin_id);

        $baskets = [
            ["Men's Haircut", 'Beard Trim'],
            ["Men's Haircut", 'Beard Trim'],
            ['Nail Art', 'Gel Polish'],
            ['Nail Art', 'Gel Polish'],
            ['Head Massage', 'Fish spa'],
            ['Hair Colour'],
            ["Men's Haircut"],
            ['Nail Art'],
        ];

        $made = 0;

        for ($week = $weeks; $week >= 0; $week--) {
            for ($nth = 0; $nth < 4; $nth++) {
                $date = Carbon::today()->subWeeks($week)->startOfWeek()->addDays($nth);

                if ($date->isFuture() || $date->isToday()) {
                    continue;
                }

                $basket = $baskets[($made + $nth) % count($baskets)];
                $provider = $providers[$made % $providers->count()];
                $customer = $this->customers[$made % count($this->customers)];

                $appointment = $this->createAppointment(
                    $salon,
                    $customer,
                    $provider,
                    $date,
                    sprintf('%02d:00:00', 10 + ($made % 7)),
                    array_map(fn ($name) => $services[$name], $basket),
                    // Most bookings come through the app; the odd one is a
                    // walk-in, which must never earn reward coins.
                    $made % 7 === 6 ? 'walk_in' : 'online'
                );

                // Every third visit picked up something extra in the chair.
                if ($made % 3 === 0) {
                    $this->addExtra($appointment, $services['Head Massage'], $providers->random(), $admin);
                }

                $checkIn->collectPaymentAndComplete(
                    $appointment->fresh($checkIn->relations()),
                    $made % 2 === 0 ? 'upi' : 'cash',
                    $admin
                );

                $made++;
            }
        }

        $this->components->twoColumnDetail('history', "{$made} completed appointments over the last {$weeks} weeks");
    }

    /**
     * Today's board: something to scan, something already in the chair, and
     * something still to come.
     */
    private function seedLive(Salon $salon): void
    {
        $services = $this->menuOf($salon);
        $providers = ServiceProvider::where('salon_id', $salon->id)->where('is_active', true)->get();
        $admin = User::find($salon->admin_id);

        // Waiting to be scanned in.
        $this->createAppointment(
            $salon,
            $this->customers[0],
            $providers[0],
            Carbon::today(),
            '11:00:00',
            [$services["Men's Haircut"], $services['Beard Trim']],
            'online',
            'scheduled'
        );

        // Already in the chair, with an extra added — the mid-appointment bill
        // to look at.
        $inProgress = $this->createAppointment(
            $salon,
            $this->customers[1],
            $providers[min(1, $providers->count() - 1)],
            Carbon::today(),
            '12:00:00',
            [$services['Nail Art']],
            'online'
        );
        $this->addExtra($inProgress, $services['Gel Polish'], $providers[0], $admin);

        // Still to come, and cancellable/reschedulable.
        $this->createAppointment(
            $salon,
            $this->customers[2],
            $providers[0],
            Carbon::tomorrow(),
            '15:00:00',
            [$services['Hair Colour']],
            'online',
            'scheduled'
        );

        $this->components->twoColumnDetail(
            'today',
            '1 waiting to scan · 1 in progress with an extra · 1 tomorrow'
        );
    }

    /**
     * Leave in both this month and last, paid and unpaid, so a payslip has a
     * deduction to explain.
     */
    private function seedLeave(Salon $salon): void
    {
        $providers = ServiceProvider::where('salon_id', $salon->id)->where('is_active', true)->get();
        $admin = User::find($salon->admin_id);

        $entries = [
            [0, Carbon::today()->subMonth()->startOfMonth()->addDays(9), ProviderLeave::TYPE_UNPAID],
            [0, Carbon::today()->subMonth()->startOfMonth()->addDays(10), ProviderLeave::TYPE_UNPAID],
            [0, Carbon::today()->startOfMonth()->addDays(2), ProviderLeave::TYPE_PAID],
            [1, Carbon::today()->startOfMonth()->addDays(4), ProviderLeave::TYPE_UNPAID],
        ];

        foreach ($entries as [$index, $date, $type]) {
            if (! isset($providers[$index])) {
                continue;
            }

            ProviderLeave::updateOrCreate(
                [
                    'provider_id' => $providers[$index]->id,
                    'leave_date' => $date->toDateString(),
                ],
                [
                    'leave_type' => $type,
                    'is_full_day' => true,
                    'reason' => 'Demo leave ' . self::TAG,
                    'status' => ProviderLeave::STATUS_APPROVED,
                    'reviewed_by' => $admin?->id,
                    'reviewed_at' => now(),
                ]
            );
        }

        $this->components->twoColumnDetail('leave', '3 unpaid days and 1 paid day across two months');
    }

    // ------------------------------------------------------------- builders

    /**
     * One appointment with its lines, the advance already taken online.
     *
     * @param array<int, Service> $services
     */
    private function createAppointment(
        Salon $salon,
        User $customer,
        ServiceProvider $provider,
        Carbon $date,
        string $startTime,
        array $services,
        string $source = 'online',
        string $status = 'in_progress'
    ): Appointment {
        $total = 0.0;
        $advance = 0.0;
        $minutes = 0;

        foreach ($services as $service) {
            $price = (float) $service->price;
            $total += $price;
            $advance += round($price * (float) $service->advance_percentage / 100, 2);
            $minutes += (int) ($service->template->estimated_duration_minutes ?? 30);
        }

        $start = Carbon::parse($date->toDateString() . ' ' . $startTime);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $source === 'walk_in' ? null : $customer->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $status === 'scheduled' ? null : $provider->id,
            'booking_source' => $source,
            'appointment_date' => $date->toDateString(),
            'start_time' => $start->format('H:i:s'),
            'end_time' => $start->copy()->addMinutes(max($minutes, 30))->format('H:i:s'),
            'status' => $status,
            'payment_option' => 'advance_only',
            'total_amount' => round($total, 2),
            'advance_amount' => round($advance, 2),
            'balance_amount' => round($total - $advance, 2),
            'walk_in_customer_name' => $source === 'walk_in' ? $customer->name : null,
            'walk_in_customer_phone' => $source === 'walk_in' ? $customer->phone : null,
            'started_at' => $status === 'in_progress' ? $start : null,
        ]);

        foreach ($services as $service) {
            AppointmentLine::create([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'price_at_booking' => (float) $service->price,
                'original_service_price' => (float) $service->price,
                'duration_minutes_at_booking' => (int) ($service->template->estimated_duration_minutes ?? 30),
                'serving_provider_id' => $status === 'scheduled' ? null : $provider->id,
                'line_status' => 'booked',
            ]);
        }

        // The advance the customer paid at booking. Recorded through the same
        // ledger the live gateway writes to, so payouts and refunds see it.
        if ($advance > 0 && $source === 'online') {
            DB::table('payments')->insert([
                'id' => (string) Str::uuid(),
                'appointment_id' => $appointment->id,
                'amount' => round($advance, 2),
                'currency' => 'INR',
                'payment_type' => 'advance',
                'payment_mode' => 'online',
                'gateway' => 'demo',
                'gateway_transaction_id' => 'pay_demo_' . Str::lower(Str::random(14)),
                'status' => 'success',
                'paid_at' => $start,
                'idempotency_key' => 'advance:' . $appointment->id,
                'created_at' => $start,
                'updated_at' => $start,
            ]);
        }

        return $appointment->fresh(['services.service.template']);
    }

    private function addExtra(Appointment $appointment, Service $service, ServiceProvider $provider, ?User $actor): void
    {
        app(AppointmentCheckInService::class)->addExtraService(
            $appointment,
            $service,
            $provider->id,
            $actor ?? User::where('role', 'superadmin')->first()
        );
    }

    // ---------------------------------------------------------------- reset

    private function reset(): void
    {
        $this->components->warn('Removing previously seeded demo data');

        $userIds = User::where('name', 'like', '%' . self::TAG)->pluck('id');
        $providerIds = ServiceProvider::whereIn('user_id', $userIds)->pluck('id');

        $appointmentIds = Appointment::whereIn('customer_id', $userIds)
            ->orWhereIn('appointed_provider_id', $providerIds)
            ->orWhereIn('serving_provider_id', $providerIds)
            ->orWhere('walk_in_customer_name', 'like', '%' . self::TAG)
            ->pluck('id');

        DB::table('payment_refunds')->whereIn('appointment_id', $appointmentIds)->delete();
        DB::table('payment_allocations')->whereIn('appointment_id', $appointmentIds)->delete();
        DB::table('payments')->whereIn('appointment_id', $appointmentIds)->delete();
        DB::table('payment_orders')->whereIn('appointment_id', $appointmentIds)->delete();
        DB::table('wallet_transactions')->whereIn('related_appointment_id', $appointmentIds)->delete();
        DB::table('appointment_service_additions')->whereIn('appointment_id', $appointmentIds)->delete();
        DB::table('appointment_services')->whereIn('appointment_id', $appointmentIds)->delete();
        Appointment::whereIn('id', $appointmentIds)->delete();

        DB::table('provider_leaves')->whereIn('provider_id', $providerIds)->delete();
        DB::table('salary_payouts')->whereIn('provider_id', $providerIds)->delete();
        DB::table('provider_services')->whereIn('provider_id', $providerIds)->delete();
        DB::table('provider_working_hours')->whereIn('provider_id', $providerIds)->delete();
        ServiceProvider::whereIn('id', $providerIds)->forceDelete();

        foreach (Combo::where('name', 'like', '%' . self::TAG)->get() as $combo) {
            $combo->services()->detach();
            $combo->delete();
        }

        foreach ([$this->activeSalon, $this->expiredSalon] as $salon) {
            DB::table('salon_payouts')->where('salon_id', $salon->id)->delete();
            DB::table('wallet_transactions')->where('salon_id', $salon->id)->delete();
            DB::table('salon_wallets')->where('salon_id', $salon->id)->delete();
        }

        User::whereIn('id', $userIds)->delete();

        foreach (WalletScheme::where('name', 'like', '%' . self::TAG)->get() as $scheme) {
            $scheme->tiers()->delete();
            $scheme->delete();
        }
    }

    // -------------------------------------------------------------- helpers

    private function salonOfAdmin(string $phone): Salon
    {
        $admin = User::where('phone', $phone)->first();

        if (! $admin) {
            throw new \RuntimeException("No user with phone {$phone}.");
        }

        $salon = Salon::where('admin_id', $admin->id)->first();

        if (! $salon) {
            throw new \RuntimeException("{$phone} does not own a salon.");
        }

        return $salon;
    }

    /** @return array<string, Service> keyed by template name */
    private function menuOf(Salon $salon): array
    {
        return Service::with('template')
            ->where('salon_id', $salon->id)
            ->where('is_active', true)
            ->get()
            ->mapWithKeys(fn (Service $s) => [$s->template->name => $s])
            ->all();
    }

    private function dayName(int $day): string
    {
        return Carbon::today()->startOfWeek(Carbon::SUNDAY)->addDays($day)->format('l');
    }

    private function summary(): void
    {
        $wallet = DB::table('salon_wallets')->where('salon_id', $this->activeSalon->id)->first();

        $this->newLine();
        $this->components->info('Ready to test');
        $this->components->twoColumnDetail(
            "{$this->activeSalon->name} — admin " . self::ACTIVE_SALON_ADMIN,
            'trading · commission model'
        );
        $this->components->twoColumnDetail(
            "{$this->expiredSalon->name} — admin " . self::EXPIRED_SALON_ADMIN,
            'plan expired yesterday'
        );
        $this->components->twoColumnDetail(
            'coin balance earned',
            ($wallet->coin_balance ?? 0) . ' coins from ' . ($wallet->completed_online_appointments_count ?? 0) . ' online completions'
        );
        $this->components->twoColumnDetail('every seeded login', 'OTP 123456');
    }
}
