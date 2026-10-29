<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\PayoutPaymentSubmission;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonSupportRequest;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The lock screen's settlements card and "Contact BookALook": what is still
 * owed either way, and a request SuperAdmin answers.
 */
class SalonSupportRequestTest extends TestCase
{
    use DatabaseTransactions;

    private User $owner;
    private User $superadmin;
    private Salon $salon;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-11-05 10:00:00');

        $u = Str::random(6);
        $this->superadmin = $this->user('superadmin', $u);
        $this->owner = $this->user('admin', $u);
        // An expired plan: the routes must still answer.
        $this->salon = Salon::create([
            'admin_id' => $this->owner->id, 'name' => "Locked {$u}", 'slug' => "locked-{$u}",
            'address' => 'x', 'status' => 'active', 'submitted_by' => $this->owner->id,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function user(string $role, string $u): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'role' => $role, 'name' => ucfirst($role) . " {$u}",
            'phone' => '3' . random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true,
        ]);
    }

    private function payout(float $net, string $status, string $start, string $end): SalonPayout
    {
        return SalonPayout::create([
            'salon_id' => $this->salon->id, 'cycle_type' => 'weekly', 'billing_type' => 'subscription',
            'cycle_start_date' => $start, 'cycle_end_date' => $end, 'status' => $status,
            'gross_amount' => 0, 'appointment_revenue' => 0, 'appointments_count' => 0,
            'commission_deducted' => 0, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => 0,
            'net_amount' => $net,
        ]);
    }

    public function test_the_summary_splits_what_is_owed_each_way(): void
    {
        $this->payout(1200, 'pending', '2026-10-19', '2026-10-25');       // BookALook owes
        $this->payout(800, 'approved', '2026-10-26', '2026-11-01');       // BookALook owes
        $owes = $this->payout(-450, 'pending', '2026-09-01', '2026-09-30'); // salon owes
        $this->payout(500, 'distributed', '2026-10-12', '2026-10-18');    // settled: not counted
        $this->payout(300, 'pending', '2026-11-02', '2026-11-08');        // still running: preview only

        PayoutPaymentSubmission::create([
            'salon_payout_id' => $owes->id, 'salon_id' => $this->salon->id, 'amount' => 450,
            'status' => PayoutPaymentSubmission::STATUS_PENDING, 'screenshot_url' => 'x.png',
        ]);

        $json = $this->actingAs($this->owner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/settlement-summary")
            ->assertOk()
            ->json();

        $this->assertSame(3, $json['pending_count']);
        $this->assertEquals(2000, $json['owed_to_salon']['amount']);
        $this->assertSame(2, $json['owed_to_salon']['count']);
        $this->assertEquals(450, $json['owed_by_salon']['amount']);
        $this->assertSame(1, $json['owed_by_salon']['under_review']);
        $this->assertCount(3, $json['settlements']);
    }

    public function test_an_owner_writes_in_and_superadmin_replies(): void
    {
        $payout = $this->payout(1200, 'pending', '2026-10-19', '2026-10-25');

        $id = $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/support-requests", [
                'topic' => 'payout_request',
                'message' => 'Please release last week\'s payout.',
                'salon_payout_id' => $payout->id,
            ])
            ->assertCreated()
            ->json('request.id');

        $list = $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/salon-requests?status=open')
            ->assertOk()
            ->json();
        $row = collect($list['data'])->firstWhere('id', $id);
        $this->assertSame($this->salon->name, $row['salon']['name']);
        $this->assertSame('Request my payout', $row['topic_label']);
        $this->assertSame($payout->id, $row['payout']['id']);

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/salon-requests/{$id}/reply", ['reply' => 'Released today.', 'resolve' => true])
            ->assertOk();

        $request = SalonSupportRequest::find($id);
        $this->assertSame('resolved', $request->status);
        $this->assertSame('Released today.', $request->reply);
        $this->assertTrue(Notification::where('user_id', $this->owner->id)->where('title', 'BookALook replied')->exists());

        $mine = $this->actingAs($this->owner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/support-requests")
            ->assertOk()
            ->json('requests');
        $this->assertSame('Released today.', $mine[0]['reply']);

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/salon-requests/{$id}/status", ['status' => 'open'])
            ->assertOk();
        $this->assertSame('open', $request->fresh()->status);
    }

    public function test_only_the_owner_and_only_their_own_settlements(): void
    {
        $staff = $this->user('service_provider', Str::random(4));
        $this->actingAs($staff, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/settlement-summary")
            ->assertForbidden();

        $otherOwner = $this->user('admin', Str::random(4));
        $other = Salon::create([
            'admin_id' => $otherOwner->id, 'name' => 'Other', 'slug' => 'other-' . Str::random(5),
            'address' => 'x', 'status' => 'active', 'submitted_by' => $otherOwner->id,
        ]);
        $theirs = SalonPayout::create([
            'salon_id' => $other->id, 'cycle_type' => 'weekly', 'billing_type' => 'subscription',
            'cycle_start_date' => '2026-10-19', 'cycle_end_date' => '2026-10-25', 'status' => 'pending',
            'gross_amount' => 0, 'appointment_revenue' => 0, 'appointments_count' => 0,
            'commission_deducted' => 0, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => 0, 'net_amount' => 10,
        ]);

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/support-requests", [
                'topic' => 'settlement_query', 'message' => 'About this one', 'salon_payout_id' => $theirs->id,
            ])
            ->assertStatus(422);

        $this->actingAs($this->owner, 'sanctum')
            ->getJson('/api/superadmin/salon-requests')
            ->assertForbidden();
    }
}
