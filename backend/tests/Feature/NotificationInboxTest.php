<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\Salon;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The inbox date filters (today, yesterday, past week, past month) and
 * deleting, for customers, salon staff and collaborators.
 */
class NotificationInboxTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-10-27 15:00:00'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function user(string $role): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'name' => ucfirst($role), 'phone' => '9'.random_int(100000000, 999999999),
            'password_hash' => 'x', 'role' => $role, 'is_active' => true,
        ]);
    }

    private function notice(User $user, string $title, Carbon $at, array $extra = []): Notification
    {
        $n = Notification::create(array_merge([
            'user_id' => $user->id,
            'type' => 'general',
            'title' => $title,
            'message' => $title,
            'is_read' => false,
        ], $extra));
        $n->forceFill(['created_at' => $at])->save();

        return $n;
    }

    /** @return array<string, Notification> */
    private function inbox(User $user, array $extra = []): array
    {
        $now = Carbon::now();

        return [
            'today' => $this->notice($user, 'Today', $now->copy()->subHour(), $extra),
            'yesterday' => $this->notice($user, 'Yesterday', $now->copy()->subDay(), $extra),
            'five_days' => $this->notice($user, 'Five days', $now->copy()->subDays(5), $extra),
            'twenty_days' => $this->notice($user, 'Twenty days', $now->copy()->subDays(20), $extra),
            'two_months' => $this->notice($user, 'Two months', $now->copy()->subDays(60), $extra),
        ];
    }

    private function titles($response): array
    {
        return collect($response->json('notifications'))->pluck('title')->all();
    }

    public function test_customers_can_filter_by_day_week_and_month(): void
    {
        $customer = $this->user('customer');
        $this->inbox($customer);

        $get = fn (string $q = '') => $this->actingAs($customer, 'sanctum')->getJson('/api/customer/notifications'.$q)->assertOk();

        $this->assertSame(['Today'], $this->titles($get('?period=today')));
        $this->assertSame(['Yesterday'], $this->titles($get('?period=yesterday')));
        $this->assertSame(['Today', 'Yesterday', 'Five days'], $this->titles($get('?period=week')));
        $this->assertSame(['Today', 'Yesterday', 'Five days', 'Twenty days'], $this->titles($get('?period=month')));
        $this->assertCount(5, $get()->json('notifications'));
        // The unread badge counts the whole inbox, whatever filter is showing.
        $this->assertSame(5, $get('?period=today')->json('unread_count'));
    }

    public function test_deleting_hides_a_notification_for_good(): void
    {
        $customer = $this->user('customer');
        $n = $this->inbox($customer);

        $this->actingAs($customer, 'sanctum')->deleteJson("/api/customer/notifications/{$n['today']->id}")->assertOk();

        $list = $this->actingAs($customer, 'sanctum')->getJson('/api/customer/notifications')->assertOk();
        $this->assertNotContains('Today', $this->titles($list));
        $this->assertSame(4, $list->json('unread_count'));

        // Kept as the record that stops the same notice being re-sent.
        $this->assertNotNull($n['today']->fresh()->dismissed_at);
    }

    public function test_bulk_delete_by_period_ids_or_all(): void
    {
        $owner = $this->user('admin');
        $n = $this->inbox($owner);
        $url = '/api/partner/notifications';

        $this->actingAs($owner, 'sanctum')->postJson("$url/delete", ['period' => 'yesterday'])->assertJsonPath('deleted', 1);
        $this->actingAs($owner, 'sanctum')->postJson("$url/delete", ['ids' => [$n['two_months']->id]])->assertJsonPath('deleted', 1);
        // Nothing said what to delete: nothing is deleted.
        $this->actingAs($owner, 'sanctum')->postJson("$url/delete", [])->assertJsonPath('deleted', 0);

        $this->assertSame(['Today', 'Five days', 'Twenty days'], $this->titles($this->actingAs($owner, 'sanctum')->getJson($url)));

        $this->actingAs($owner, 'sanctum')->postJson("$url/delete", ['all' => true])->assertJsonPath('deleted', 3);
        $this->assertSame([], $this->titles($this->actingAs($owner, 'sanctum')->getJson($url)));
    }

    public function test_nobody_can_delete_someone_elses_notification(): void
    {
        $alice = $this->user('customer');
        $bob = $this->user('customer');
        $hers = $this->notice($alice, 'Hers', Carbon::now());

        $this->actingAs($bob, 'sanctum')->deleteJson("/api/customer/notifications/{$hers->id}")->assertNotFound();
        $this->actingAs($bob, 'sanctum')->postJson('/api/customer/notifications/delete', ['ids' => [$hers->id]])->assertJsonPath('deleted', 0);
        $this->actingAs($bob, 'sanctum')->postJson('/api/customer/notifications/delete', ['all' => true]);

        $this->assertNull($hers->fresh()->dismissed_at);
    }

    public function test_collaborators_filter_and_delete_within_their_own_salons(): void
    {
        $collaborator = $this->user('collaborator');
        $owner = $this->user('admin');
        $mine = Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => 'Mine', 'slug' => 'mine-'.Str::random(5),
            'address' => 'x', 'status' => 'active', 'submitted_by' => $collaborator->id, 'assigned_collaborator_id' => $collaborator->id,
        ]);
        $notMine = Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => 'Not mine', 'slug' => 'not-mine-'.Str::random(5),
            'address' => 'x', 'status' => 'active', 'submitted_by' => $owner->id,
        ]);

        $this->inbox($collaborator, ['related_salon_id' => $mine->id]);
        $other = $this->notice($collaborator, 'Elsewhere', Carbon::now(), ['related_salon_id' => $notMine->id]);

        $url = '/api/partner/collaborator/notifications';
        $this->assertSame(['Today'], $this->titles($this->actingAs($collaborator, 'sanctum')->getJson("$url?period=today")));

        $this->actingAs($collaborator, 'sanctum')->deleteJson("$url/{$other->id}")->assertNotFound();
        $this->actingAs($collaborator, 'sanctum')->postJson("$url/delete", ['period' => 'week'])->assertJsonPath('deleted', 3);

        $this->assertSame(['Twenty days', 'Two months'], $this->titles($this->actingAs($collaborator, 'sanctum')->getJson($url)));
        $this->assertNull($other->fresh()->dismissed_at);
    }
}
