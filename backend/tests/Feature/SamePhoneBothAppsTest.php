<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SubArea;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\ActivatesSalons;
use Tests\TestCase;

/**
 * One phone number can have a customer account (Customer app) and one partner
 * account (Partner app). Inside the partner side it is still only one of
 * owner, staff or collaborator.
 */
class SamePhoneBothAppsTest extends TestCase
{
    use DatabaseTransactions;
    use ActivatesSalons;

    private const CODE = '246810';

    private function phone(): string
    {
        return '9'.random_int(100000000, 999999999);
    }

    /** Lets [phone] sign in with a fixed code, without sending anything. */
    private function allowLogin(string $phone): void
    {
        config(['services.otp.review_phones' => [$phone], 'services.otp.review_code' => self::CODE]);
    }

    private function user(string $role, ?string $phone = null, ?string $email = null): User
    {
        return User::create([
            'name' => ucfirst($role).' '.Str::random(4),
            'phone' => $phone ?? $this->phone(),
            'email' => $email,
            'password_hash' => 'x',
            'role' => $role,
            'is_active' => true,
        ]);
    }

    private function salon(User $owner): Salon
    {
        return $this->activateSalon(Salon::create([
            'admin_id' => $owner->id,
            'name' => 'Same Phone Salon',
            'slug' => 'same-phone-'.Str::random(6),
            'address' => '1 Test St',
            'status' => 'active',
            'submitted_by' => $owner->id,
        ]));
    }

    /** A week off, so the staff payload needs no shift times. */
    private function weekOff(): array
    {
        return array_map(fn ($d) => ['day_of_week' => $d, 'is_weekly_off' => true], range(0, 6));
    }

    // ---------------------------------------------------- account type rule

    public function test_account_type_follows_the_role(): void
    {
        $this->assertSame(User::ACCOUNT_CUSTOMER, $this->user('customer')->account_type);
        foreach (['admin', 'service_provider', 'collaborator', 'superadmin'] as $role) {
            $this->assertSame(User::ACCOUNT_PARTNER, $this->user($role)->account_type, $role);
        }
    }

    public function test_a_number_can_have_one_customer_and_one_partner_account(): void
    {
        $phone = $this->phone();
        $this->user('service_provider', $phone);
        $this->user('customer', $phone);

        $this->assertSame(2, User::where('phone', $phone)->count());
    }

    public function test_the_database_still_refuses_two_accounts_on_the_same_side(): void
    {
        $phone = $this->phone();
        $this->user('admin', $phone);

        $this->expectException(QueryException::class);
        $this->user('collaborator', $phone);
    }

    public function test_the_resync_migration_repairs_a_mistyped_owner_account(): void
    {
        // What stale API code did in production: an owner saved with the
        // column default instead of the model hook.
        $owner = $this->user('admin');
        \Illuminate\Support\Facades\DB::table('users')->where('id', $owner->id)->update(['account_type' => 'customer']);

        (require database_path('migrations/2026_11_22_000002_resync_user_account_type_with_role.php'))->up();

        $this->assertSame(User::ACCOUNT_PARTNER, $owner->fresh()->account_type);

        // And the Customer app no longer mistakes it for a customer account.
        $this->allowLogin($owner->phone);
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $owner->phone, 'otp' => self::CODE])
            ->assertOk()
            ->assertJsonPath('requires_registration', true);
    }

    // ---------------------------------------------------- Customer app login

    public function test_a_staff_members_number_can_sign_up_in_the_customer_app(): void
    {
        $phone = $this->phone();
        $staff = $this->user('service_provider', $phone);
        $this->allowLogin($phone);

        // Used to be refused with "registered as a partner"; now it is a new customer.
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $phone, 'otp' => self::CODE])
            ->assertOk()
            ->assertJsonPath('requires_registration', true);

        $city = City::whereHas('subAreas')->first() ?? City::first();
        $area = $city ? SubArea::where('city_id', $city->id)->first() : null;
        if (! $city || ! $area) {
            $this->markTestSkipped('needs a city with an area');
        }

        $this->postJson('/api/customer/auth/complete-profile', [
            'phone' => $phone,
            'name' => 'Riya as a customer',
            'city_id' => $city->id,
            'sub_area_id' => $area->id,
        ])->assertOk()->assertJsonPath('user.role', 'customer');

        // Two accounts now; the staff account is untouched.
        $this->assertSame('service_provider', $staff->fresh()->role);
        $this->assertSame(1, User::customerAccounts()->where('phone', $phone)->count());
    }

    public function test_customer_login_finds_the_customer_account_not_the_partner_one(): void
    {
        $phone = $this->phone();
        $this->user('admin', $phone);
        $customer = $this->user('customer', $phone);
        $this->allowLogin($phone);

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $phone, 'otp' => self::CODE])
            ->assertOk()
            ->assertJsonPath('user.id', $customer->id)
            ->assertJsonPath('user.role', 'customer');
    }

    // ---------------------------------------------------- Partner app login

    public function test_partner_login_ignores_a_customer_account_on_the_number(): void
    {
        $phone = $this->phone();
        $this->user('customer', $phone);
        $this->allowLogin($phone);

        // Only a customer account: the Partner app treats it as a new partner.
        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $phone, 'otp' => self::CODE])
            ->assertOk()
            ->assertJsonPath('status', 'new_user');
    }

    public function test_partner_login_finds_the_partner_account_when_both_exist(): void
    {
        $phone = $this->phone();
        $this->user('customer', $phone);
        $owner = $this->user('admin', $phone);
        $this->allowLogin($phone);

        $body = $this->postJson('/api/partner/auth/verify-otp', ['phone' => $phone, 'otp' => self::CODE])
            ->assertOk()
            ->json();

        $this->assertSame('admin', $body['role'] ?? $body['user']['role'] ?? null);
        $this->assertNotSame('new_user', $body['status'] ?? null);
        $this->assertTrue(User::partnerAccounts()->whereKey($owner->id)->exists());
    }

    // ---------------------------------------------------- adding staff

    public function test_a_customers_number_can_be_added_as_staff(): void
    {
        $owner = $this->user('admin');
        $salon = $this->salon($owner);
        $phone = $this->phone();
        $customer = $this->user('customer', $phone);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/staff", [
                'name' => 'New Stylist',
                'phone' => $phone,
                'working_hours' => $this->weekOff(),
            ])
            ->assertSuccessful();

        $this->assertSame(1, User::partnerAccounts()->where('phone', $phone)->where('role', 'service_provider')->count());
        $this->assertSame('customer', $customer->fresh()->role, 'the customer account is left as it was');
    }

    public function test_a_number_that_already_has_a_partner_account_cannot_be_added_as_staff(): void
    {
        $owner = $this->user('admin');
        $salon = $this->salon($owner);
        $collaborator = $this->user('collaborator');

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/staff", [
                'name' => 'Already a collaborator',
                'phone' => $collaborator->phone,
                'working_hours' => $this->weekOff(),
            ])
            ->assertStatus(422)
            ->assertJsonPath('errors.phone.0', User::PARTNER_PHONE_TAKEN);
    }

    // ---------------------------------------------------- SuperAdmin login

    public function test_superadmin_login_is_not_confused_by_a_customer_with_the_same_email(): void
    {
        $email = 'boss'.Str::random(6).'@example.test';
        User::create([
            'name' => 'Boss', 'phone' => $this->phone(), 'email' => $email,
            'password_hash' => 'secret-pass', 'role' => 'superadmin', 'is_active' => true,
        ]);
        $this->user('customer', null, $email);

        $this->postJson('/api/superadmin/auth/login', ['email' => $email, 'password' => 'secret-pass'])
            ->assertOk();
    }
}
