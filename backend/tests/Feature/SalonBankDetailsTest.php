<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\City;
use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\ServiceProvider;
use App\Models\SubArea;
use App\Models\User;
use App\Services\BankDetailsService;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\ActivatesSalons;
use Tests\TestCase;

/**
 * Where BookALook pays a salon: optional at sign-up, editable later by the
 * owner and SuperAdmin, never shown in full except to SuperAdmin on request.
 */
class SalonBankDetailsTest extends TestCase
{
    use ActivatesSalons;
    use DatabaseTransactions;

    private const VALID = [
        'bank_account_holder_name' => 'Asha Kulkarni',
        'bank_name' => 'HDFC Bank',
        'bank_account_number' => '50100123456789',
        'bank_ifsc' => 'hdfc0001234',
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

    private function salon(?User $owner = null): Salon
    {
        $owner ??= $this->user('admin');

        return Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => 'Bank Salon',
            'slug' => 'bank-salon-'.Str::random(6), 'address' => '1 Test St', 'status' => 'active',
            'submitted_by' => $owner->id,
        ]);
    }

    private function owner(Salon $salon): User
    {
        return User::find($salon->admin_id);
    }

    public function test_the_owner_saves_bank_details_and_only_sees_the_last_four_digits(): void
    {
        $salon = $this->salon();

        $res = $this->actingAs($this->owner($salon), 'sanctum')
            ->putJson("/api/partner/salons/{$salon->id}/bank-details", self::VALID)
            ->assertOk()
            ->assertJsonPath('bank_details.ifsc', 'HDFC0001234')
            ->assertJsonPath('bank_details.account_number_last4', '6789')
            ->assertJsonPath('bank_details.account_number', null)
            ->assertJsonPath('bank_details.has_required', true);

        $this->assertStringNotContainsString('50100123456789', $res->getContent());

        // Encrypted at rest; the model decrypts it.
        $raw = DB::table('salons')->where('id', $salon->id)->value('bank_account_number');
        $this->assertNotSame('50100123456789', $raw);
        $this->assertSame('50100123456789', $salon->fresh()->bank_account_number);
    }

    public function test_bank_fields_never_ride_along_in_ordinary_salon_json(): void
    {
        $salon = $this->salon();
        app(BankDetailsService::class)->apply($salon, app(BankDetailsService::class)->validate(self::VALID));

        $json = json_encode($salon->fresh()->toArray());
        $this->assertStringNotContainsString('bank_', $json);
    }

    public function test_half_an_account_is_refused(): void
    {
        $salon = $this->salon();

        $this->actingAs($this->owner($salon), 'sanctum')
            ->putJson("/api/partner/salons/{$salon->id}/bank-details", [
                'bank_account_number' => '50100123456789',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['bank_ifsc', 'bank_name', 'bank_account_holder_name']);
    }

    public function test_bad_values_are_refused(): void
    {
        $salon = $this->salon();
        $owner = $this->owner($salon);

        foreach ([
            'bank_ifsc' => 'HDFC1234567',
            'bank_account_number' => '12AB',
            'bank_upi_id' => 'not-a-upi',
            'bank_account_holder_name' => 'Asha 123',
        ] as $field => $bad) {
            $this->actingAs($owner, 'sanctum')
                ->putJson("/api/partner/salons/{$salon->id}/bank-details", [$field => $bad] + self::VALID)
                ->assertStatus(422)
                ->assertJsonValidationErrors([$field]);
        }
    }

    public function test_a_blank_account_number_on_update_keeps_the_saved_one(): void
    {
        $salon = $this->salon();
        $owner = $this->owner($salon);

        $this->actingAs($owner, 'sanctum')->putJson("/api/partner/salons/{$salon->id}/bank-details", self::VALID)->assertOk();

        $this->actingAs($owner, 'sanctum')
            ->putJson("/api/partner/salons/{$salon->id}/bank-details", [
                'bank_account_number' => '',
                'bank_upi_id' => 'asha.new@okaxis',
            ] + array_diff_key(self::VALID, ['bank_account_number' => 1, 'bank_upi_id' => 1]))
            ->assertOk()
            ->assertJsonPath('bank_details.upi_id', 'asha.new@okaxis')
            ->assertJsonPath('bank_details.account_number_last4', '6789');
    }

    public function test_nobody_else_can_read_or_change_them(): void
    {
        $salon = $this->salon();
        $otherOwner = $this->user('admin');
        $staffUser = $this->user('service_provider');
        ServiceProvider::create(['id' => (string) Str::uuid(), 'user_id' => $staffUser->id, 'salon_id' => $salon->id, 'is_active' => true]);

        foreach ([$otherOwner, $staffUser, $this->user('customer')] as $intruder) {
            $this->actingAs($intruder, 'sanctum')->getJson("/api/partner/salons/{$salon->id}/bank-details")->assertStatus(403);
            $this->actingAs($intruder, 'sanctum')->putJson("/api/partner/salons/{$salon->id}/bank-details", self::VALID)->assertStatus(403);
        }

        $this->actingAs($this->owner($salon), 'sanctum')
            ->putJson('/api/superadmin/salons/'.$salon->id.'/bank-details', self::VALID)
            ->assertStatus(403);

        $this->assertNull($salon->fresh()->bank_account_number);
    }

    public function test_the_home_warning_shows_only_with_a_live_plan_and_missing_details(): void
    {
        $salon = $this->salon();
        $owner = $this->owner($salon);

        // No plan yet: no warning.
        $this->actingAs($owner, 'sanctum')->getJson("/api/partner/salons/{$salon->id}/bank-details")
            ->assertJsonPath('show_missing_warning', false);

        $this->activateSalon($salon);

        $this->actingAs($owner, 'sanctum')->getJson("/api/partner/salons/{$salon->id}/bank-details")
            ->assertJsonPath('show_missing_warning', true);

        // A UPI ID alone is not enough to pay a settlement.
        $this->actingAs($owner, 'sanctum')
            ->putJson("/api/partner/salons/{$salon->id}/bank-details", ['bank_upi_id' => 'asha@okhdfcbank'])
            ->assertJsonPath('show_missing_warning', true);

        $this->actingAs($owner, 'sanctum')
            ->putJson("/api/partner/salons/{$salon->id}/bank-details", self::VALID)
            ->assertJsonPath('show_missing_warning', false);
    }

    public function test_superadmin_edits_are_audited_without_the_account_number(): void
    {
        $salon = $this->salon();
        $admin = $this->user('superadmin');

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/superadmin/salons/{$salon->id}/bank-details", self::VALID)
            ->assertOk()
            ->assertJsonPath('bank_details.account_number', null);

        $log = AuditLog::where('action', AuditLog::SALON_BANK_DETAILS_UPDATED)->where('entity_id', $salon->id)->latest()->first();
        $this->assertNotNull($log);
        $this->assertStringNotContainsString('50100123456789', json_encode($log->toArray()));
    }

    public function test_superadmin_can_reveal_the_full_number_and_it_is_audited(): void
    {
        $salon = $this->salon();
        $admin = $this->user('superadmin');
        $this->actingAs($admin, 'sanctum')->putJson("/api/superadmin/salons/{$salon->id}/bank-details", self::VALID);

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/superadmin/salons/{$salon->id}/bank-details")
            ->assertJsonPath('bank_details.account_number', null);

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/superadmin/salons/{$salon->id}/bank-details?reveal=1")
            ->assertJsonPath('bank_details.account_number', '50100123456789');

        $this->assertTrue(
            AuditLog::where('action', AuditLog::SALON_BANK_DETAILS_REVEALED)->where('entity_id', $salon->id)->exists()
        );
    }

    public function test_the_website_form_takes_optional_bank_details(): void
    {
        $city = City::first() ?? City::create(['id' => (string) Str::uuid(), 'name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $area = SubArea::where('city_id', $city->id)->first()
            ?? SubArea::create(['id' => (string) Str::uuid(), 'city_id' => $city->id, 'name' => 'Baner', 'is_active' => true]);

        $base = [
            'salon_name' => 'Web Salon', 'owner_name' => 'Asha', 'phone' => '9876501234',
            'city_id' => $city->id, 'sub_area_id' => $area->id,
            'street_address' => '1 Road', 'pincode' => '411045',
        ];

        // Without any: still accepted.
        $this->postJson('/api/enquiries', $base)->assertCreated();

        // With bad ones: refused, not silently dropped.
        $this->postJson('/api/enquiries', $base + ['bank_ifsc' => 'BAD'] + self::VALID)->assertStatus(422);

        $id = $this->postJson('/api/enquiries', $base + self::VALID)->assertCreated()->json('enquiry.id');
        $enquiry = SalonEnquiry::find($id);
        $this->assertSame('HDFC0001234', $enquiry->bank_ifsc);
        $this->assertSame('50100123456789', $enquiry->bank_account_number);
        $this->assertStringNotContainsString('50100123456789', json_encode($enquiry->toArray()));
    }

    public function test_website_details_carry_over_to_the_onboarded_salon(): void
    {
        $bank = app(BankDetailsService::class);
        $enquiry = new SalonEnquiry();
        $bank->apply($enquiry->forceFill([
            'salon_name' => 'Carry', 'owner_name' => 'A', 'phone' => '9876500000', 'status' => 'new',
        ]), $bank->validate(self::VALID));

        $salon = $this->salon();
        $bank->carryFromEnquiry($enquiry, $salon);

        $this->assertTrue($bank->hasRequired($salon->fresh()));
        $this->assertSame('6789', $salon->fresh()->bank_account_last4);
    }

    public function test_registration_works_with_and_without_bank_details(): void
    {
        $owner = $this->user('admin');
        $city = City::first() ?? City::create(['id' => (string) Str::uuid(), 'name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $area = SubArea::where('city_id', $city->id)->first()
            ?? SubArea::create(['id' => (string) Str::uuid(), 'city_id' => $city->id, 'name' => 'Baner', 'is_active' => true]);
        $photo = \Illuminate\Http\UploadedFile::fake()->createWithContent(
            'cover.png',
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
        );

        $base = [
            'salon_name' => 'App Salon', 'street_address' => '1 Road', 'city_id' => $city->id,
            'sub_area_id' => $area->id, 'pincode' => '411045', 'cover_image' => $photo,
        ];

        $plain = $this->actingAs($owner, 'sanctum')->post('/api/partner/register', $base, ['Accept' => 'application/json'])
            ->assertCreated()->json('salon.id');
        $this->assertFalse(app(BankDetailsService::class)->hasAny(Salon::find($plain)));

        $withBank = $this->actingAs($owner, 'sanctum')
            ->post('/api/partner/register', ['salon_name' => 'App Salon Two', 'cover_image' => $photo] + self::VALID + $base, ['Accept' => 'application/json'])
            ->assertCreated()->json('salon.id');
        $this->assertTrue(app(BankDetailsService::class)->hasRequired(Salon::find($withBank)));
    }
}
