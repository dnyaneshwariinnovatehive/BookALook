<?php

namespace Tests\Feature;

use App\Console\Commands\CheckSubscriptions;
use App\Models\City;
use App\Models\Notification;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\Notifications\NotificationService;
use App\Support\BillingModel;
use App\Support\Notifications\NotificationAction;
use App\Support\Notifications\NotificationType;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The collaborator's side of the subscription conversation.
 *
 * A collaborator cannot pay for a salon they onboarded, so the whole feature is
 * built around one asymmetry: they are told early, and their only lever is the
 * phone. These tests exist to hold that line — the warnings land, the owner is
 * reachable, a renewal ends the chase, and nothing at all happens for a salon
 * that is no longer theirs.
 *
 * Runs in a transaction so it can use the development database without leaving
 * anything behind.
 */
class CollaboratorSubscriptionNoticeTest extends TestCase
{
    use DatabaseTransactions;

    // ------------------------------------------------------- the warning ladder

    public function test_the_collaborator_is_warned_a_week_out_and_again_at_three_days(): void
    {
        [$salon, $admin, $collaborator] = $this->fixture();
        $this->givenSubscription($salon, endsInDays: 7);

        $this->runReminders();

        $early = $this->noticesFor($collaborator, $salon);
        $this->assertCount(1, $early);
        $this->assertStringContainsString('7 days', $early->first()->title);

        // The second rung is a separate window, not a resend of the first: the
        // salon is closer to going dark and the call is now overdue, not early.
        $this->givenSubscription($salon, endsInDays: 3);

        $this->runReminders();

        $this->assertCount(2, $this->noticesFor($collaborator, $salon));
    }

    public function test_the_warning_carries_the_owners_number_and_no_renewal_path(): void
    {
        [$salon, $admin, $collaborator] = $this->fixture();
        $this->givenSubscription($salon, endsInDays: 7);

        $this->runReminders();

        $notice = $this->noticesFor($collaborator, $salon)->first();

        // A collaborator has no wallet for somebody else's salon, so offering
        // them "renew" would be a button that can only fail.
        $this->assertSame(NotificationAction::CALL_OWNER, $notice->data['action']);
        $this->assertSame($admin->phone, $notice->data['owner_phone']);
        $this->assertSame($salon->id, $notice->data['salon_id']);
    }

    public function test_the_owner_only_hears_about_it_inside_their_own_window(): void
    {
        [$salon, $admin] = $this->fixture(assigned: false);

        // Seven days out is the collaborator's first rung. If widening the query
        // to reach them had dragged the owner's inbox along, this would pass and
        // be wrong.
        $this->givenSubscription($salon, endsInDays: 7);
        $this->setPolicy('subscription_expiry_warning_days', 3);
        $this->runReminders();

        $this->assertSame(0, Notification::where('user_id', $admin->id)
            ->where('related_salon_id', $salon->id)
            ->where('type', CheckSubscriptions::TYPE_EXPIRING)
            ->count());

        // Inside the owner's own window they still get it.
        $this->givenSubscription($salon, endsInDays: 2);

        $this->runReminders();

        $this->assertSame(1, Notification::where('user_id', $admin->id)
            ->where('related_salon_id', $salon->id)
            ->where('type', CheckSubscriptions::TYPE_EXPIRING)
            ->count());
    }

    // -------------------------------------------------------------- after lapse

    public function test_a_lapsed_salon_is_reported_daily_and_deduplicated_within_the_day(): void
    {
        [$salon, $collaborator] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 2);

        $this->runReminders();

        $lapsed = $this->noticesFor($collaborator, $salon)
            ->where('type', NotificationType::ASSIGNED_SALON_EXPIRING);

        $this->assertCount(1, $lapsed);
        $this->assertTrue($lapsed->first()->data['lapsed']);
        // Negative days left would render as an absurd number; the app needs a
        // flag, not a countdown from somewhere behind zero.
        $this->assertSame(-2, $lapsed->first()->data['days_left']);

        // The scheduler runs hourly. Twice in a day must still be one notice.
        $this->runReminders();

        $this->assertCount(1, $this->noticesFor($collaborator, $salon)
            ->where('type', NotificationType::ASSIGNED_SALON_EXPIRING));

        // Tomorrow is a new day, and the salon is still offline. Frozen time is
        // process-global, so it gets handed back whatever the assertions do.
        try {
            Carbon::setTestNow(Carbon::today()->addDay());
            $this->runReminders();

            $this->assertCount(2, $this->noticesFor($collaborator, $salon)
                ->where('type', NotificationType::ASSIGNED_SALON_EXPIRING));
        } finally {
            Carbon::setTestNow();
        }
    }

    // ----------------------------------------------------------- the happy end

    public function test_a_renewal_tells_the_collaborator_the_call_landed(): void
    {
        [$salon, $collaborator] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 2);

        $this->runReminders();
        $this->assertGreaterThan(0, $this->noticesFor($collaborator, $salon)->count());

        $subscription = $this->givenSubscription($salon, endsInDays: 30);
        app(NotificationService::class)
            ->assignedSalonRenewed($salon->fresh('admin'), $subscription->fresh('plan'));

        $renewed = $this->noticesFor($collaborator, $salon)
            ->where('type', NotificationType::ASSIGNED_SALON_RENEWED);

        $this->assertCount(1, $renewed);
        // Confirmation only. The chase is over, so nothing here should read as
        // work still to be done.
        $this->assertStringNotContainsString('call', strtolower($renewed->first()->message));
    }

    public function test_one_renewal_is_confirmed_once_even_if_the_caller_retries(): void
    {
        [$salon, $collaborator] = $this->fixture();
        $this->givenSubscription($salon, endsInDays: 30);

        $service = app(NotificationService::class);

        $service->assignedSalonRenewed($salon->fresh('admin'), $subscription->fresh('plan'));
        $service->assignedSalonRenewed($salon->fresh('admin'), $subscription->fresh('plan'));

        $this->assertSame(1, $this->noticesFor($collaborator, $salon)
            ->where('type', NotificationType::ASSIGNED_SALON_RENEWED)
            ->count());
    }

    // ------------------------------------------------------- the ownership line

    public function test_a_salon_reassigned_away_is_never_reported_again(): void
    {
        [$salon, $collaborator] = $this->fixture();
        $this->givenSubscription($salon, endsInDays: 7);

        $salon->update(['assigned_collaborator_id' => null]);

        $this->runReminders();

        $this->assertCount(0, $this->noticesFor($collaborator, $salon));
    }

    // ------------------------------------------------------------- the inbox

    public function test_the_inbox_holds_notices_for_the_salons_still_assigned(): void
    {
        [$mine] = $this->fixture();
        [$theirs] = $this->fixture();
        [$collaborator] = $this->fixtureCollaborator();

        $this->givenNotice($mine, $collaborator, NotificationType::ASSIGNED_SALON_EXPIRING);
        $this->givenNotice($theirs, $collaborator, NotificationType::ASSIGNED_SALON_EXPIRING);

        $body = $this->actingAs($collaborator, 'sanctum')
            ->getJson('/api/partner/collaborator/notifications')
            ->assertStatus(200)
            ->json();

        $ids = collect($body['notifications'])->pluck('salon_id');
        $this->assertTrue($ids->contains($mine->id));
        $this->assertFalse($ids->contains($theirs->id));
    }

    public function test_the_bell_counts_only_the_notices_worth_interrupting_for(): void
    {
        [$salon] = $this->fixture();
        [$collaborator] = $this->fixtureCollaborator();

        $this->givenNotice($salon, $collaborator, NotificationType::ASSIGNED_SALON_EXPIRING);
        $this->givenNotice($salon, $collaborator, NotificationType::ASSIGNED_SALON_RENEWED);
        $this->givenNotice($salon, $collaborator, NotificationType::BOOKING_CONFIRMED);

        $body = $this->actingAs($collaborator, 'sanctum')
            ->getJson('/api/partner/collaborator/notifications')
            ->assertStatus(200)
            ->json();

        $this->assertSame(3, $body['unread_count']);
        $this->assertSame(2, $body['important_count']);
    }

    public function test_a_notice_is_newest_first_and_reading_one_drops_the_badge(): void
    {
        [$salon] = $this->fixture();
        [$collaborator] = $this->fixtureCollaborator();

        $older = $this->givenNotice($salon, $collaborator, NotificationType::ASSIGNED_SALON_EXPIRING);
        $newer = $this->givenNotice($salon, $collaborator, NotificationType::ASSIGNED_SALON_RENEWED);

        $this->actingAs($collaborator, 'sanctum')
            ->postJson("/api/partner/collaborator/notifications/{$newer->id}/read")
            ->assertStatus(200);

        $this->assertTrue($newer->fresh()->is_read);
        $this->assertFalse($older->fresh()->is_read);

        $body = $this->actingAs($collaborator, 'sanctum')
            ->getJson('/api/partner/collaborator/notifications')
            ->assertStatus(200)
            ->json();

        $this->assertSame(
            [$newer->id, $older->id],
            collect($body['notifications'])->pluck('id')->all()
        );
        $this->assertSame(1, $body['important_count']);
        $this->assertSame(1, $body['unread_count']);
    }

    public function test_a_collaborator_cannot_read_a_notice_belonging_to_somebody_elses_salon(): void
    {
        [$salon] = $this->fixture();
        [$collaborator] = $this->fixtureCollaborator();

        // Reassigned away, so the salon is out of scope but the id is guessable.
        $notice = $this->givenNotice($salon, $collaborator, NotificationType::ASSIGNED_SALON_EXPIRING);
        $salon->update(['assigned_collaborator_id' => null]);

        $this->actingAs($collaborator, 'sanctum')
            ->postJson("/api/partner/collaborator/notifications/{$notice->id}/read")
            ->assertStatus(200);

        $this->assertFalse($notice->fresh()->is_read);
    }

    public function test_mark_all_read_leaves_other_collaborators_notices_alone(): void
    {
        [$salon] = $this->fixture();
        [$mine, $theirs] = [$this->fixtureCollaborator(), $this->fixtureCollaborator()];

        $a = $this->givenNotice($salon, $mine, NotificationType::ASSIGNED_SALON_EXPIRING);
        $b = $this->givenNotice($salon, $theirs, NotificationType::ASSIGNED_SALON_EXPIRING);

        $this->actingAs($mine, 'sanctum')
            ->postJson('/api/partner/collaborator/notifications/read-all')
            ->assertStatus(200)
            ->assertJsonPath('updated', 1);

        $this->assertTrue($a->fresh()->is_read);
        $this->assertFalse($b->fresh()->is_read);
    }

    public function test_a_salon_owner_cannot_use_the_collaborator_inbox(): void
    {
        [$salon, $admin] = $this->fixture(assigned: false);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/partner/collaborator/notifications')
            ->assertStatus(403);
    }

    // ------------------------------------------------------------- fixtures

    /**
     * A salon, its owner, and the collaborator holding it.
     *
     * With assigned: false there is no collaborator, which is how the owner-only
     * tests get a salon nobody is being chased about.
     *
     * @return array{0: Salon, 1: User, 2: ?User}
     */
    private function fixture(bool $assigned = true): array
    {
        $salon = $this->givenSalon();

        $collaborator = $assigned ? $this->fixtureCollaborator() : null;

        if ($collaborator) {
            $salon->update(['assigned_collaborator_id' => $collaborator->id]);
        }

        return [$salon->fresh(), User::findOrFail($salon->admin_id), $collaborator];
    }

    private function fixtureCollaborator(): User
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        return User::create([
            'name' => "Collaborator {$unique}",
            'phone' => '7' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'collaborator',
            'is_active' => true,
        ]);
    }

    private function givenSalon(): Salon
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Owner {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        return Salon::create([
            'admin_id' => $admin->id,
            'name' => "Notice Salon {$unique}",
            'slug' => "notice-salon-{$unique}",
            'address' => 'Test address',
            'city_id' => City::where('is_active', true)->value('id'),
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);
    }

    private function givenSubscription(
        Salon $salon,
        ?int $endedDaysAgo = null,
        ?int $endsInDays = null
    ): SalonSubscription {
        $plan = SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $end = $endedDaysAgo !== null
            ? Carbon::today()->subDays($endedDaysAgo)
            : Carbon::today()->addDays($endsInDays ?? 30);

        return SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => (clone $end)->subDays(30),
            'end_date' => $end,
            'status' => $endedDaysAgo !== null ? 'expired' : 'active',
        ]);
    }

    private function givenNotice(Salon $salon, User $recipient, string $type): Notification
    {
        return Notification::create([
            'user_id' => $recipient->id,
            'related_salon_id' => $salon->id,
            'type' => $type,
            'title' => "About {$salon->name}",
            'message' => 'Something happened.',
            'data' => [
                'action' => NotificationType::defaultActionFor($type),
                'salon_id' => $salon->id,
                'owner_phone' => '900000000',
                'days_left' => 5,
                'lapsed' => false,
            ],
            'is_read' => false,
        ]);
    }

    /** @return \Illuminate\Database\Eloquent\Collection<int, Notification> */
    private function noticesFor(User $collaborator, Salon $salon)
    {
        return Notification::where('user_id', $collaborator->id)
            ->where('related_salon_id', $salon->id)
            ->get();
    }

    private function setPolicy(string $key, $value): void
    {
        PlatformPolicySetting::updateOrCreate(
            ['setting_key' => $key],
            ['setting_value' => (string) $value, 'data_type' => 'integer']
        );
    }

    private function runReminders(): void
    {
        $this->artisan('app:check-subscriptions --force-reminders')->assertExitCode(0);
    }
}
