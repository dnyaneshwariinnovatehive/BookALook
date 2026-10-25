<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\SalaryPayout;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Str;
use Tests\TestCase;

class PayrollOwnerAndNotificationPruneTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();
        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
    }

    private function user(string $role, string $tag): User
    {
        return User::create([
            'id' => (string) Str::uuid(),
            'role' => $role,
            'name' => "{$tag} {$this->unique}",
            'phone' => '5'.substr((string) crc32($this->unique.$tag), 0, 9),
            'password_hash' => bcrypt('password'),
            'is_active' => true,
        ]);
    }

    // ── Payroll ───────────────────────────────────────────────────────────

    public function test_owner_working_as_a_provider_is_not_on_the_salary_page(): void
    {
        $owner = $this->user('admin', 'own');
        $salon = Salon::create([
            'admin_id' => $owner->id,
            'name' => "Pay {$this->unique}",
            'slug' => "pay-{$this->unique}",
            'address' => '1 Pay Street',
            'status' => 'active',
            'submitted_by' => $owner->id,
        ]);
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Growth Plan', 'price' => 999, 'duration_days' => 30, 'is_active' => true,
        ]);
        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => now()->subDays(5)->toDateString(),
            'end_date' => now()->addDays(25)->toDateString(),
            'status' => 'active',
        ]);

        // "Admin as service provider" on: the owner has a provider profile too.
        $ownerAsProvider = ServiceProvider::create([
            'user_id' => $owner->id, 'salon_id' => $salon->id, 'base_salary' => 0, 'is_active' => true,
        ]);
        $staff = ServiceProvider::create([
            'user_id' => $this->user('service_provider', 'st')->id, 'salon_id' => $salon->id, 'base_salary' => 15000, 'is_active' => true,
        ]);

        // A payslip left over from before owners were excluded stays hidden.
        SalaryPayout::create([
            'provider_id' => $ownerAsProvider->id,
            'salon_id' => $salon->id,
            'salary_month' => now()->startOfMonth()->toDateString(),
            'base_salary_snapshot' => 0,
            'commission_percentage_snapshot' => 0,
            'commission_earned' => 0,
            'working_days_in_month' => 26,
            'daily_rate' => 0,
            'paid_leave_days' => 0,
            'unpaid_leave_days' => 0,
            'unpaid_leave_deduction' => 0,
            'other_adjustments' => 0,
            'total_payable' => 0,
            'status' => SalaryPayout::STATUS_PENDING,
        ]);

        $response = $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/payroll")
            ->assertStatus(200);

        $providerIds = collect($response->json('payslips'))->pluck('provider_id');
        $this->assertTrue($providerIds->contains($staff->id));
        $this->assertFalse($providerIds->contains($ownerAsProvider->id));
        $this->assertSame(1, $response->json('totals.staff'));

        // And no new payslip is made for the owner.
        $this->assertSame(1, SalaryPayout::where('provider_id', $ownerAsProvider->id)->count());
    }

    // ── Notification pruning ──────────────────────────────────────────────

    private function notice(User $user, int $daysOld, bool $read): Notification
    {
        $n = Notification::create([
            'user_id' => $user->id,
            'type' => 'general',
            'title' => "Notice {$daysOld} {$this->unique}",
            'message' => 'Hello',
            'is_read' => $read,
            'read_at' => $read ? now()->subDays($daysOld) : null,
        ]);
        $n->forceFill(['created_at' => now()->subDays($daysOld), 'updated_at' => now()->subDays($daysOld)])->saveQuietly();

        return $n;
    }

    public function test_prune_removes_old_notifications_and_keeps_recent_ones(): void
    {
        $customer = $this->user('customer', 'cu');
        $partner = $this->user('admin', 'pa');

        $readOld = $this->notice($customer, 31, true);
        $readRecent = $this->notice($customer, 10, true);
        $unreadMid = $this->notice($partner, 45, false);
        $unreadAncient = $this->notice($partner, 91, false);

        Artisan::call('model:prune', ['--model' => [Notification::class]]);

        $this->assertDatabaseMissing('notifications', ['id' => $readOld->id]);
        $this->assertDatabaseMissing('notifications', ['id' => $unreadAncient->id]);
        $this->assertDatabaseHas('notifications', ['id' => $readRecent->id]);
        $this->assertDatabaseHas('notifications', ['id' => $unreadMid->id]);
    }

    public function test_retention_follows_config(): void
    {
        config(['notifications.retention.read_days' => 7, 'notifications.retention.unread_days' => 14]);
        $user = $this->user('customer', 'cu');

        $read = $this->notice($user, 8, true);
        $unread = $this->notice($user, 15, false);
        $fresh = $this->notice($user, 3, false);

        Artisan::call('model:prune', ['--model' => [Notification::class]]);

        $this->assertDatabaseMissing('notifications', ['id' => $read->id]);
        $this->assertDatabaseMissing('notifications', ['id' => $unread->id]);
        $this->assertDatabaseHas('notifications', ['id' => $fresh->id]);
    }
}
