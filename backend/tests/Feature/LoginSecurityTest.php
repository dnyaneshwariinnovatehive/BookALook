<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\WhatsappAutomation;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * Sign-in: a code works only for the phone it was sent to, once, for ten
 * minutes; wrong guesses run out; there is no demo code in production; the
 * sign-in endpoints are rate limited; and logins expire.
 *
 * Every test makes its own users with random numbers inside a transaction.
 */
class LoginSecurityTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();
        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
        Cache::flush();
        Cache::store('state')->flush();
        Queue::fake();
        config(['services.otp.review_phones' => [], 'services.otp.review_code' => '']);
    }

    private function phone(string $tag): string
    {
        return '9'.substr(str_pad((string) crc32($this->unique.$tag), 9, '0'), 0, 9);
    }

    private function user(string $role, string $tag): User
    {
        return User::create([
            'id' => (string) Str::uuid(),
            'role' => $role,
            'name' => "{$tag} {$this->unique}",
            'phone' => $this->phone($tag),
            'email' => "{$tag}.{$this->unique}@example.test",
            'password_hash' => bcrypt('secret-password'),
            'is_active' => true,
        ]);
    }

    private function liveWhatsAppOtp(): void
    {
        WhatsappAutomation::updateOrCreate(
            ['key' => 'whatsapp_otp'],
            ['name' => 'OTP', 'description' => 'OTP', 'audience' => 'customer', 'frequency_label' => 'on demand', 'is_enabled' => true, 'aisensy_campaign_name' => 'otp_campaign'],
        );
    }

    private function inProduction(): void
    {
        $this->app->detectEnvironment(fn () => 'production');
    }

    private function sendCustomer(string $phone): string
    {
        $this->postJson('/api/customer/auth/send-otp', ['phone' => $phone])->assertOk();

        return Cache::store('state')->get('otp:customer:'.$phone);
    }

    private function sendPartner(string $phone): string
    {
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $phone])->assertOk();

        return Cache::store('state')->get('otp:partner:'.$phone);
    }

    // 1, 3 — customer: 123456 is refused, the real code works.
    public function test_123456_does_not_sign_a_customer_in_and_the_real_code_does(): void
    {
        $this->liveWhatsAppOtp();
        $user = $this->user('customer', 'c');
        $real = $this->sendCustomer($user->phone);

        if ($real !== '123456') {
            $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
                ->assertStatus(422);
        }

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => $real])
            ->assertOk()->assertJsonStructure(['access_token']);
    }

    // 2, 3 — partner: 123456 is refused, the real code works.
    public function test_123456_does_not_sign_a_partner_in_and_the_real_code_does(): void
    {
        $this->liveWhatsAppOtp();
        $owner = $this->user('admin', 'o');
        $real = $this->sendPartner($owner->phone);

        if ($real !== '123456') {
            $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => '123456'])
                ->assertStatus(400);
        }

        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => $real])
            ->assertOk()->assertJsonPath('status', 'existing_user')->assertJsonStructure(['token']);
    }

    public function test_no_code_works_for_a_phone_that_was_never_sent_one(): void
    {
        $user = $this->user('customer', 'c');

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertStatus(422);
        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertStatus(400);
    }

    // 4
    public function test_a_wrong_code_is_rejected(): void
    {
        $this->liveWhatsAppOtp();
        $user = $this->user('customer', 'c');
        $real = $this->sendCustomer($user->phone);
        $wrong = $real === '000000' ? '111111' : '000000';

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => $wrong])
            ->assertStatus(422)->assertJsonMissingPath('access_token');
    }

    // 5
    public function test_an_expired_code_is_rejected(): void
    {
        $this->liveWhatsAppOtp();
        $owner = $this->user('admin', 'o');
        $real = $this->sendPartner($owner->phone);

        $this->travel(11)->minutes();

        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => $real])
            ->assertStatus(400);
    }

    // 6
    public function test_a_code_cannot_be_used_twice(): void
    {
        $this->liveWhatsAppOtp();
        $user = $this->user('customer', 'c');
        $real = $this->sendCustomer($user->phone);

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => $real])->assertOk();
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => $real])->assertStatus(422);
    }

    // 7
    public function test_a_code_sent_to_one_number_does_not_sign_in_another(): void
    {
        $this->liveWhatsAppOtp();
        $mine = $this->user('admin', 'a');
        $theirs = $this->user('admin', 'b');
        $code = $this->sendPartner($mine->phone);
        $this->sendPartner($theirs->phone);

        if (Cache::store('state')->get('otp:partner:'.$theirs->phone) !== $code) {
            $this->postJson('/api/partner/auth/verify-otp', ['phone' => $theirs->phone, 'otp' => $code])
                ->assertStatus(400);
        }
    }

    public function test_a_customer_code_does_not_work_in_the_partner_flow(): void
    {
        $this->liveWhatsAppOtp();
        $user = $this->user('admin', 'o');
        $code = $this->sendCustomer($user->phone);

        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $user->phone, 'otp' => $code])
            ->assertStatus(400);
    }

    public function test_five_wrong_codes_throw_the_code_away(): void
    {
        $this->liveWhatsAppOtp();
        $owner = $this->user('admin', 'o');
        $real = $this->sendPartner($owner->phone);
        $wrong = $real === '000000' ? '111111' : '000000';

        foreach (range(1, 5) as $_) {
            $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => $wrong])
                ->assertStatus(400);
        }

        $this->assertNull(Cache::store('state')->get('otp:partner:'.$owner->phone), 'the code is gone; a new one is needed');
    }

    public function test_outside_production_the_demo_code_still_works_when_whatsapp_is_off(): void
    {
        $user = $this->user('customer', 'c');

        $this->assertSame('123456', $this->sendCustomer($user->phone));
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertOk()->assertJsonStructure(['access_token']);
    }

    public function test_in_production_there_is_no_demo_code(): void
    {
        $this->inProduction();
        $user = $this->user('customer', 'c');

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $user->phone])->assertStatus(503);
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $user->phone])->assertStatus(503);
        $this->assertNull(Cache::store('state')->get('otp:customer:'.$user->phone));

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertStatus(422);

        // A phone change is refused too, rather than accepting a demo code.
        $this->actingAs($user, 'sanctum')
            ->postJson('/api/customer/profile/phone/send-otp', ['phone' => $this->phone('new')])
            ->assertStatus(422);
    }

    public function test_in_production_the_real_whatsapp_code_still_works(): void
    {
        $this->inProduction();
        $this->liveWhatsAppOtp();
        $user = $this->user('customer', 'c');
        $real = $this->sendCustomer($user->phone);

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => $real])
            ->assertOk()->assertJsonStructure(['access_token']);
    }

    public function test_a_review_number_signs_in_with_its_fixed_code_and_nothing_else_does(): void
    {
        $this->inProduction();
        $this->liveWhatsAppOtp();
        $reviewer = $this->user('customer', 'r');
        $other = $this->user('customer', 'x');
        config(['services.otp.review_phones' => ['+91 '.$reviewer->phone], 'services.otp.review_code' => '424242']);

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $reviewer->phone])->assertOk();
        $this->assertNull(Cache::store('state')->get('otp:customer:'.$reviewer->phone), 'a review number is never sent a code');

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $reviewer->phone, 'otp' => '424242'])
            ->assertOk()->assertJsonStructure(['access_token']);

        $this->sendCustomer($other->phone);
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $other->phone, 'otp' => '424242'])
            ->assertStatus(422);
    }

    public function test_a_review_code_that_is_not_six_digits_is_ignored(): void
    {
        $reviewer = $this->user('customer', 'r');
        config(['services.otp.review_phones' => [$reviewer->phone], 'services.otp.review_code' => '1']);

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $reviewer->phone, 'otp' => '000001'])
            ->assertStatus(422);
    }

    // 8
    public function test_verifying_is_rate_limited_per_phone_with_retry_information(): void
    {
        $user = $this->user('customer', 'c');
        $this->sendCustomer($user->phone);

        foreach (range(1, 5) as $_) {
            $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '000000'])
                ->assertStatus(422);
        }

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertStatus(429)
            ->assertHeader('Retry-After')
            ->assertJsonStructure(['message', 'retry_after']);

        // Another customer is not held up.
        $other = $this->user('customer', 'd');
        $this->sendCustomer($other->phone);
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $other->phone, 'otp' => '123456'])->assertOk();
    }

    // 9
    public function test_asking_for_codes_is_rate_limited_per_phone_whatever_the_format(): void
    {
        $phone = $this->phone('p');

        $this->postJson('/api/partner/auth/send-otp', ['phone' => $phone])->assertOk();
        $this->postJson('/api/partner/auth/send-otp', ['phone' => '+91 '.$phone])->assertOk();
        $this->postJson('/api/partner/auth/send-otp', ['phone' => '0'.$phone])->assertOk();

        $res = $this->postJson('/api/partner/auth/send-otp', ['phone' => '+91-'.substr($phone, 0, 5).' '.substr($phone, 5)])
            ->assertStatus(429)->assertHeader('Retry-After');
        $this->assertGreaterThan(0, $res->json('retry_after'));

        // Another number is not held up.
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $this->phone('q')])->assertOk();

        // Ten minutes later the number can ask again.
        $this->travel(11)->minutes();
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $phone])->assertOk();
    }

    public function test_asking_for_codes_is_rate_limited_per_ip(): void
    {
        config(['services.otp.limits.send_per_ip_hour' => 4]);

        foreach (range(1, 4) as $i) {
            $this->postJson('/api/customer/auth/send-otp', ['phone' => $this->phone("ip{$i}")])->assertOk();
        }
        $this->postJson('/api/customer/auth/send-otp', ['phone' => $this->phone('ip5')])->assertStatus(429);

        // A different address is not affected.
        $this->withServerVariables(['REMOTE_ADDR' => '10.1.2.3'])
            ->postJson('/api/customer/auth/send-otp', ['phone' => $this->phone('ip6')])->assertOk();
    }

    public function test_a_forwarded_for_header_does_not_change_the_ip_used(): void
    {
        config(['services.otp.limits.send_per_ip_hour' => 2]);

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $this->phone('f1')])->assertOk();
        $this->postJson('/api/customer/auth/send-otp', ['phone' => $this->phone('f2')])->assertOk();
        $this->withHeader('X-Forwarded-For', '203.0.113.9')
            ->postJson('/api/customer/auth/send-otp', ['phone' => $this->phone('f3')])->assertStatus(429);
    }

    // 10
    public function test_superadmin_login_is_rate_limited_per_email_and_ip(): void
    {
        $admin = $this->user('superadmin', 'sa');

        foreach (range(1, 5) as $_) {
            $this->postJson('/api/superadmin/auth/login', ['email' => $admin->email, 'password' => 'wrong'])
                ->assertStatus(401);
        }
        $this->postJson('/api/superadmin/auth/login', ['email' => $admin->email, 'password' => 'secret-password'])
            ->assertStatus(429)->assertJsonPath('success', false)->assertJsonStructure(['retry_after']);
    }

    public function test_superadmin_login_is_rate_limited_per_ip_across_emails(): void
    {
        foreach (range(1, 20) as $i) {
            $this->postJson('/api/superadmin/auth/login', ['email' => "nobody{$i}.{$this->unique}@example.test", 'password' => 'x'])
                ->assertStatus(401);
        }
        $this->postJson('/api/superadmin/auth/login', ['email' => "nobody21.{$this->unique}@example.test", 'password' => 'x'])
            ->assertStatus(429);
    }

    public function test_superadmin_tokens_last_twelve_hours(): void
    {
        $admin = $this->user('superadmin', 'sa');

        $token = $this->postJson('/api/superadmin/auth/login', ['email' => $admin->email, 'password' => 'secret-password'])
            ->assertOk()->json('token');

        $row = PersonalAccessToken::findToken($token);
        $this->assertEqualsWithDelta(now()->addHours(12)->timestamp, $row->expires_at->timestamp, 60);
    }

    // 11
    public function test_an_app_login_expires_after_ninety_days(): void
    {
        $owner = $this->user('admin', 'o');
        $token = $owner->createToken('partner-auth-token')->plainTextToken;

        $this->withToken($token)->getJson('/api/partner/auth/check')->assertOk();

        PersonalAccessToken::findToken($token)->forceFill(['created_at' => now()->subDays(91)])->save();
        $this->app['auth']->forgetGuards();

        $this->withToken($token)->getJson('/api/partner/auth/check')->assertStatus(401);
    }

    public function test_a_superadmin_token_past_its_twelve_hours_is_rejected(): void
    {
        $admin = $this->user('superadmin', 'sa');
        $token = $admin->createToken('superadmin-token', ['*'], now()->addHours(12))->plainTextToken;

        $this->withToken($token)->postJson('/api/superadmin/auth/logout')->assertOk();
        $this->app['auth']->forgetGuards();

        $token = $admin->createToken('superadmin-token', ['*'], now()->addHours(12))->plainTextToken;
        $this->travel(13)->hours();

        $this->withToken($token)->postJson('/api/superadmin/auth/logout')->assertStatus(401);
    }

    // 12 — sign-up, sign-in and logout still work end to end.
    public function test_a_new_customer_signs_up_and_logs_out_and_the_token_stops_working(): void
    {
        $phone = $this->phone('new');
        $city = \App\Models\City::query()->first() ?? \App\Models\City::create(['name' => "City {$this->unique}"]);
        $area = \App\Models\SubArea::query()->where('city_id', $city->id)->first()
            ?? \App\Models\SubArea::create(['city_id' => $city->id, 'name' => "Area {$this->unique}"]);

        $this->sendCustomer($phone);
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $phone, 'otp' => '123456'])
            ->assertOk()->assertJsonPath('requires_registration', true);

        $token = $this->postJson('/api/customer/auth/complete-profile', [
            'phone' => $phone, 'name' => 'New Customer', 'city_id' => $city->id, 'sub_area_id' => $area->id,
        ])->assertSuccessful()->json('access_token');
        $this->assertNotEmpty($token);

        $this->withToken($token)->postJson('/api/customer/auth/logout')->assertOk();
        $this->app['auth']->forgetGuards();
        $this->assertNull(PersonalAccessToken::findToken($token));
        $this->withToken($token)->postJson('/api/customer/auth/logout')->assertStatus(401);
    }

    public function test_an_existing_partner_signs_in_and_their_token_works(): void
    {
        $owner = $this->user('admin', 'o');
        $this->sendPartner($owner->phone);

        $token = $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => '123456'])
            ->assertOk()->json('token');

        $this->withToken($token)->getJson('/api/partner/auth/check')->assertOk();
    }
}
