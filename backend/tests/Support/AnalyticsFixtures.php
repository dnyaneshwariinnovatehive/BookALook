<?php

namespace Tests\Support;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonPayoutItem;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Rows for the money-in-pocket and analytics tests: users, salons with a team
 * member to book with, bookings, payments, refunds, payouts and plan payments,
 * plus helpers that call the endpoints as SuperAdmin.
 *
 * The suite shares a database with other tests, so tests compare the change
 * their own rows make (cash position) or work inside a city of their own.
 */
trait AnalyticsFixtures
{
    protected User $superadmin;
    protected User $owner;
    protected string $tag;

    /** @var array<string, string> salon id => a team member to book with */
    protected array $providers = [];

    protected function setUpAnalyticsFixtures(): void
    {
        Carbon::setTestNow('2026-11-05 10:00:00');
        config(['services.payments.razorpay.fee_percent' => 2.36]);

        $this->tag = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->superadmin = $this->user('superadmin');
        $this->owner = $this->user('admin');
    }

    protected function user(string $role, array $extra = []): User
    {
        return User::create(array_merge([
            'id' => (string) Str::uuid(), 'role' => $role, 'name' => ucfirst($role) . ' ' . Str::random(4),
            'phone' => '4' . random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true,
        ], $extra));
    }

    protected function salon(string $name, array $extra = []): Salon
    {
        $salon = Salon::create(array_merge([
            'admin_id' => $this->owner->id, 'name' => "{$name} {$this->tag}", 'slug' => Str::slug($name) . '-' . Str::random(8),
            'address' => 'x', 'status' => 'active', 'submitted_by' => $this->owner->id,
        ], $extra));
        $this->providers[$salon->id] = ServiceProvider::create(['user_id' => $this->user('service_provider')->id, 'salon_id' => $salon->id, 'is_active' => true])->id;

        return $salon;
    }

    protected function booking(Salon $salon, string $date, string $status, float $total, array $extra = []): Appointment
    {
        return Appointment::create(array_merge([
            'salon_id' => $salon->id,
            'appointed_provider_id' => $this->providers[$salon->id],
            'booking_source' => 'online',
            'appointment_date' => $date,
            'start_time' => '11:00:00',
            'end_time' => '11:30:00',
            'status' => $status,
            'total_amount' => $total,
            'final_billed_amount' => $status === 'completed' ? $total : null,
            'advance_amount' => 0,
            'balance_amount' => $total,
        ], $extra));
    }

    protected function pay(Appointment $a, float $amount, ?string $gateway = 'razorpay', string $at = '2026-10-20 10:00:00', string $type = 'advance', string $status = 'success'): string
    {
        $id = (string) Str::uuid();
        DB::table('payments')->insert([
            'id' => $id, 'appointment_id' => $a->id, 'amount' => $amount, 'payment_type' => $type,
            'payment_mode' => $gateway ? 'online' : 'cash', 'gateway' => $gateway, 'status' => $status,
            'paid_at' => $at, 'created_at' => $at, 'updated_at' => $at,
        ]);

        return $id;
    }

    protected function refund(Appointment $a, string $paymentId, float $amount, string $status, string $at = '2026-10-21 10:00:00', string $reason = 'Cancelled in time'): void
    {
        DB::table('payment_refunds')->insert([
            'id' => (string) Str::uuid(), 'payment_id' => $paymentId, 'appointment_id' => $a->id, 'amount' => $amount,
            'reason' => $reason, 'status' => $status, 'created_at' => $at, 'updated_at' => $at,
        ]);
    }

    protected function payout(Salon $salon, string $status, float $gross, float $commission, float $net, array $claims = [], string $start = '2026-10-01', float $coins = 0): SalonPayout
    {
        $payout = SalonPayout::create([
            'salon_id' => $salon->id, 'cycle_type' => 'monthly', 'billing_type' => 'commission',
            'cycle_start_date' => $start, 'cycle_end_date' => Carbon::parse($start)->endOfMonth()->toDateString(), 'status' => $status,
            'gross_amount' => $gross, 'appointment_revenue' => $gross, 'appointments_count' => count($claims),
            'commission_deducted' => $commission, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => $coins,
            'net_amount' => $net, 'distributed_at' => $status === 'distributed' ? '2026-10-31 12:00:00' : null,
        ]);
        foreach ($claims as $a) {
            SalonPayoutItem::create([
                'salon_payout_id' => $payout->id, 'kind' => SalonPayoutItem::KIND_BOOKING, 'appointment_id' => $a->id,
                'appointment_status' => $a->status, 'gross_amount' => $gross, 'commission_base' => $gross,
                'commission_rate' => 10, 'commission_amount' => $commission, 'refund_amount' => 0, 'net_amount' => $gross - $commission,
            ]);
        }

        return $payout;
    }

    protected function planPayment(Salon $salon, string $status, ?float $cash, string $at = '2026-10-15 10:00:00', float $coins = 0, ?float $price = null): void
    {
        $plan = SubscriptionPlan::create(['name' => 'Plan ' . Str::random(5), 'price' => $price ?? $cash, 'validity_days' => 30, 'is_active' => true]);
        DB::table('subscription_payment_requests')->insert([
            'salon_id' => $salon->id, 'subscription_plan_id' => $plan->id, 'billing_type' => 'subscription',
            'screenshot_url' => 'x.png', 'status' => $status, 'coins_to_redeem' => 0, 'coin_discount_inr' => $coins,
            'amount_payable_inr' => $cash, 'created_at' => $at, 'updated_at' => $at,
        ]);
    }

    protected function cash(): array
    {
        return $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/reports/cash-position')
            ->assertOk()
            ->json();
    }

    protected function line(array $json, string $group, string $key): float
    {
        return (float) collect($json[$group])->firstWhere('key', $key)['amount'];
    }

    protected function section(string $section, array $query = []): array
    {
        return $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/reports/analytics/' . $section . '?' . http_build_query($query))
            ->assertOk()
            ->assertJsonPath('success', true)
            ->json();
    }

    /** A city of our own, with one area in it. @return array{0: string, 1: string} [city id, area id] */
    protected function city(string $name = 'Testpur'): array
    {
        $city = (string) Str::uuid();
        DB::table('cities')->insert(['id' => $city, 'name' => "{$name} {$this->tag}", 'state' => 'Test', 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        $area = (string) Str::uuid();
        DB::table('sub_areas')->insert(['id' => $area, 'city_id' => $city, 'name' => 'Lakeside', 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);

        return [$city, $area];
    }
}
