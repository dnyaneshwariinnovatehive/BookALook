<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\City;
use App\Models\Notification;
use App\Models\ProviderLeave;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\SubArea;
use App\Models\User;
use App\Services\BankDetailsService;
use App\Services\Notifications\PushPayload;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\ActivatesSalons;
use Tests\TestCase;

/**
 * One owner, several branches: each branch's staff and bookings are its own
 * owner's alone, the owner serves customers at one branch only, a branch
 * cannot close on its booked customers, and the inbox and bank details know
 * which branch is which.
 */
class MultiSalonOwnerTest extends TestCase
{
    use ActivatesSalons;
    use DatabaseTransactions;

    private const BANK = [
        'bank_account_holder_name' => 'Asha Kulkarni',
        'bank_name' => 'HDFC Bank',
        'bank_account_number' => '50100123456789',
        'bank_ifsc' => 'HDFC0001234',
        'bank_upi_id' => 'asha@okhdfcbank',
    ];

    private function user(string $role): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'name' => ucfirst($role).' '.Str::random(4),
            'phone' => '9'.random_int(100000000, 999999999), 'password_hash' => 'x',
            'role' => $role, 'is_active' => true,
        ]);
    }

    private function salon(User $owner, string $name, string $status = 'active'): Salon
    {
        return $this->activateSalon(Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => $name,
            'slug' => Str::slug($name).'-'.Str::random(6), 'address' => '1 Test St', 'status' => $status,
            'submitted_by' => $owner->id,
        ]));
    }

    private function provider(Salon $salon, ?User $user = null, bool $active = true): ServiceProvider
    {
        return ServiceProvider::create([
            'id' => (string) Str::uuid(), 'user_id' => ($user ?? $this->user('service_provider'))->id,
            'salon_id' => $salon->id, 'is_active' => $active,
        ]);
    }

    private function booking(Salon $salon, ServiceProvider $provider, string $status = 'scheduled', ?string $date = null): Appointment
    {
        return Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $this->user('customer')->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => $date ?? Carbon::tomorrow()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => $status,
            'payment_option' => 'advance_only',
            'total_amount' => 1000,
            'advance_amount' => 300,
            'balance_amount' => 700,
        ]);
    }

    // ------------------------------------------------------------ ownership

    public function test_only_the_owner_reads_or_changes_a_salons_staff_and_leave(): void
    {
        $owner = $this->user('admin');
        $salon = $this->salon($owner, 'Glow Baner');
        $staff = $this->provider($salon);
        $leave = ProviderLeave::create([
            'provider_id' => $staff->id, 'leave_date' => Carbon::tomorrow()->toDateString(),
            'leave_type' => 'unpaid', 'is_full_day' => true, 'status' => 'pending',
        ]);

        $strangers = [$this->user('admin'), $this->user('customer'), $this->user('service_provider')];

        foreach ($strangers as $stranger) {
            $as = $this->actingAs($stranger, 'sanctum');
            $as->getJson("/api/partner/salons/{$salon->id}/staff")->assertForbidden();
            $as->putJson("/api/partner/salons/{$salon->id}/staff/{$staff->id}", ['name' => 'Hijacked'])->assertForbidden();
            $as->deleteJson("/api/partner/salons/{$salon->id}/staff/{$staff->id}")->assertForbidden();
            $as->getJson("/api/partner/salons/{$salon->id}/leaves")->assertForbidden();
            $as->putJson("/api/partner/salons/{$salon->id}/leaves/{$leave->id}/status", ['status' => 'approved'])->assertForbidden();
            $as->postJson("/api/partner/salons/{$salon->id}/staff", ['name' => 'X'])->assertForbidden();
        }

        $this->assertNotSame('Hijacked', $staff->user->fresh()->name);
        $this->assertSame('pending', $leave->fresh()->status);
        $this->assertNotNull(ServiceProvider::find($staff->id));

        $this->actingAs($owner, 'sanctum')->getJson("/api/partner/salons/{$salon->id}/staff")->assertOk();
        $this->actingAs($owner, 'sanctum')->getJson("/api/partner/salons/{$salon->id}/leaves")
            ->assertOk()->assertJsonCount(1, 'leaves');
    }

    public function test_an_owner_cannot_read_another_owners_bookings(): void
    {
        $owner = $this->user('admin');
        $salon = $this->salon($owner, 'Glow Baner');
        $this->booking($salon, $this->provider($salon));

        $this->actingAs($this->user('admin'), 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertForbidden();

        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertOk();
    }

    // -------------------------------------------------- owner as a provider

    public function test_an_owner_working_at_one_salon_is_told_so_at_the_other(): void
    {
        $owner = $this->user('admin');
        $a = $this->salon($owner, 'Glow Baner');
        $b = $this->salon($owner, 'Glow Aundh');
        $profile = $this->provider($a, $owner);

        $status = $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$b->id}/admin-provider")
            ->assertOk()
            ->assertJsonPath('is_provider_enabled', false)
            ->assertJsonPath('provider', null)
            ->assertJsonPath('provider_elsewhere.salon_id', $a->id)
            ->assertJsonPath('provider_elsewhere.salon_name', 'Glow Baner')
            ->json('provider_elsewhere.message');
        $this->assertStringContainsString('Glow Baner', $status);
        $this->assertStringContainsString('only one salon', $status);

        // Turning it on at B is refused, and A keeps its provider.
        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$b->id}/admin-provider/toggle", ['enabled' => true])
            ->assertStatus(409)
            ->assertJsonPath('error_code', 'PROVIDER_AT_OTHER_SALON');
        // Nor can B switch off A's.
        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$b->id}/admin-provider/toggle", ['enabled' => false])
            ->assertStatus(409);

        $profile->refresh();
        $this->assertSame($a->id, $profile->salon_id);
        $this->assertTrue((bool) $profile->is_active);

        // At A, everything is as before.
        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$a->id}/admin-provider")
            ->assertJsonPath('is_provider_enabled', true)
            ->assertJsonPath('provider_elsewhere', null);
    }

    public function test_a_switched_off_profile_with_bookings_stays_with_its_salon(): void
    {
        $owner = $this->user('admin');
        $a = $this->salon($owner, 'Glow Baner');
        $b = $this->salon($owner, 'Glow Aundh');
        $profile = $this->provider($a, $owner, active: false);
        $this->booking($a, $profile, 'completed', Carbon::yesterday()->toDateString());

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$b->id}/admin-provider/toggle", ['enabled' => true])
            ->assertStatus(409);

        $this->assertSame($a->id, $profile->fresh()->salon_id);
    }

    public function test_an_unused_switched_off_profile_may_move_to_another_salon(): void
    {
        $owner = $this->user('admin');
        $a = $this->salon($owner, 'Glow Baner');
        $b = $this->salon($owner, 'Glow Aundh');
        $profile = $this->provider($a, $owner, active: false);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$b->id}/admin-provider/toggle", ['enabled' => true])
            ->assertOk()
            ->assertJsonPath('is_provider_enabled', true)
            ->assertJsonPath('provider_elsewhere', null);

        $this->assertSame($b->id, $profile->fresh()->salon_id);
    }

    // ------------------------------------------------------------- closing

    public function test_a_salon_with_booked_customers_cannot_be_deactivated(): void
    {
        $owner = $this->user('admin');
        $salon = $this->salon($owner, 'Glow Baner');
        $this->booking($salon, $this->provider($salon), 'scheduled');

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/deactivate")
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'HAS_UPCOMING_APPOINTMENTS');

        $this->assertSame('active', $salon->fresh()->status);
    }

    public function test_a_booking_waiting_for_a_new_time_also_blocks_deactivation(): void
    {
        $owner = $this->user('admin');
        $salon = $this->salon($owner, 'Glow Baner');
        $this->booking($salon, $this->provider($salon), 'awaiting_reschedule', Carbon::yesterday()->toDateString());

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/deactivate")
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'HAS_UPCOMING_APPOINTMENTS');
    }

    // --------------------------------------------------------- bank details

    public function test_bank_details_can_be_copied_from_the_owners_other_salon(): void
    {
        $owner = $this->user('admin');
        $a = $this->salon($owner, 'Glow Baner');
        $b = $this->salon($owner, 'Glow Aundh');
        $bank = app(BankDetailsService::class);
        $bank->apply($a, $bank->validate(self::BANK));

        $shown = $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$b->id}/bank-details")
            ->assertOk()
            ->assertJsonCount(1, 'other_salons')
            ->assertJsonPath('other_salons.0.salon_id', $a->id)
            ->assertJsonPath('other_salons.0.account_number_last4', '6789')
            ->assertJsonPath('other_salons.0.account_number', null);
        $this->assertStringNotContainsString('50100123456789', $shown->getContent());

        $copied = $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$b->id}/bank-details/copy", ['from_salon_id' => $a->id])
            ->assertOk()
            ->assertJsonPath('bank_details.has_required', true)
            ->assertJsonPath('bank_details.ifsc', 'HDFC0001234');
        $this->assertStringNotContainsString('50100123456789', $copied->getContent());

        $b->refresh();
        $this->assertSame('50100123456789', $b->bank_account_number);
        $this->assertSame('6789', $b->bank_account_last4);
        $this->assertSame($owner->id, $b->bank_details_updated_by);

        $this->actingAs($owner, 'sanctum')
            ->getJson('/api/partner/bank-details/saved')
            ->assertOk()
            ->assertJsonCount(2, 'salons');
    }

    public function test_bank_details_cannot_be_copied_from_someone_elses_salon(): void
    {
        $owner = $this->user('admin');
        $mine = $this->salon($owner, 'Glow Baner');
        $theirs = $this->salon($this->user('admin'), 'Other Owner');
        $bank = app(BankDetailsService::class);
        $bank->apply($theirs, $bank->validate(self::BANK));

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$mine->id}/bank-details/copy", ['from_salon_id' => $theirs->id])
            ->assertStatus(422);

        $this->assertNull($mine->fresh()->bank_account_number);

        // And a salon with nothing to copy is not offered.
        $this->actingAs($owner, 'sanctum')
            ->getJson('/api/partner/bank-details/saved')
            ->assertJsonCount(0, 'salons');
    }

    public function test_a_new_branch_can_register_with_another_salons_bank_details(): void
    {
        $owner = $this->user('admin');
        $first = $this->salon($owner, 'Glow Baner');
        $bank = app(BankDetailsService::class);
        $bank->apply($first, $bank->validate(self::BANK));

        $city = City::first() ?? City::create(['id' => (string) Str::uuid(), 'name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $area = SubArea::where('city_id', $city->id)->first()
            ?? SubArea::create(['id' => (string) Str::uuid(), 'city_id' => $city->id, 'name' => 'Baner', 'is_active' => true]);
        $form = fn (string $name) => [
            'salon_name' => $name, 'street_address' => '1 Road', 'city_id' => $city->id,
            'sub_area_id' => $area->id, 'pincode' => '411045',
            'cover_image' => UploadedFile::fake()->createWithContent(
                'cover.png',
                base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
            ),
        ];

        $id = $this->actingAs($owner, 'sanctum')
            ->post('/api/partner/register', $form('Glow Aundh') + ['bank_copy_from_salon_id' => $first->id], ['Accept' => 'application/json'])
            ->assertCreated()
            ->json('salon.id');
        $this->assertSame('50100123456789', Salon::find($id)->bank_account_number);

        // Not from a salon that is not theirs.
        $theirs = $this->salon($this->user('admin'), 'Other Owner');
        $bank->apply($theirs, $bank->validate(self::BANK));
        $this->actingAs($owner, 'sanctum')
            ->post('/api/partner/register', $form('Glow Kothrud') + ['bank_copy_from_salon_id' => $theirs->id], ['Accept' => 'application/json'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('bank_copy_from_salon_id');
    }

    // ---------------------------------------------------------- notifications

    public function test_the_inbox_names_each_salon_and_filters_by_one(): void
    {
        $owner = $this->user('admin');
        $a = $this->salon($owner, 'Glow Baner');
        $b = $this->salon($owner, 'Glow Aundh');
        foreach ([[$a, 'A1'], [$a, 'A2'], [$b, 'B1']] as [$salon, $title]) {
            Notification::create([
                'user_id' => $owner->id, 'type' => 'general', 'title' => $title,
                'message' => $title, 'is_read' => false, 'related_salon_id' => $salon->id,
            ]);
        }

        $all = $this->actingAs($owner, 'sanctum')->getJson('/api/partner/notifications')->assertOk();
        $all->assertJsonCount(3, 'notifications')->assertJsonCount(2, 'salons');
        $names = collect($all->json('notifications'))->pluck('salon_name', 'title');
        $this->assertSame('Glow Baner', $names['A1']);
        $this->assertSame('Glow Aundh', $names['B1']);
        $counts = collect($all->json('salons'))->pluck('unread_count', 'name');
        $this->assertSame(2, $counts['Glow Baner']);
        $this->assertSame(1, $counts['Glow Aundh']);

        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/notifications?salon_id={$b->id}")
            ->assertJsonCount(1, 'notifications')
            ->assertJsonPath('notifications.0.title', 'B1');

        // Deleting "all" while filtered to A deletes only A's.
        $this->actingAs($owner, 'sanctum')
            ->postJson('/api/partner/notifications/delete', ['all' => true, 'salon_id' => $a->id])
            ->assertOk()
            ->assertJsonPath('deleted', 2);
        $this->actingAs($owner, 'sanctum')
            ->getJson('/api/partner/notifications')
            ->assertJsonCount(1, 'notifications');
    }

    public function test_a_single_salon_owner_gets_no_salon_filter(): void
    {
        $owner = $this->user('admin');
        $this->salon($owner, 'Only Salon');

        $this->actingAs($owner, 'sanctum')
            ->getJson('/api/partner/notifications')
            ->assertOk()
            ->assertJsonCount(0, 'salons');
    }

    public function test_pushes_name_the_salon_for_an_owner_with_several(): void
    {
        $owner = $this->user('admin');
        $a = $this->salon($owner, 'Glow Baner');
        $n = Notification::create([
            'user_id' => $owner->id, 'type' => 'new_booking', 'title' => 'New booking',
            'message' => 'Riya booked for tomorrow', 'is_read' => false, 'related_salon_id' => $a->id,
        ]);

        // One salon: the title is left alone.
        $this->assertSame('New booking', PushPayload::fromNotification($n)->title);

        $this->salon($owner, 'Glow Aundh');
        $this->assertSame('Glow Baner · New booking', PushPayload::fromNotification($n)->title);
    }
}
