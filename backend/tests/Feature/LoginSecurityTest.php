<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\WhatsappAutomation;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * Sign-in: a code works only for the phone it was sent to, wrong guesses run
 * out, the sign-in endpoints are rate limited, and logins expire.
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

    public function test_123456_no_longer_signs_a_customer_in_when_whatsapp_codes_are_on(): void
    {
        $this->liveWhatsAppOtp();
        $user = $this->user('customer', 'c');

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $user->phone])->assertOk();
        $real = Cache::get('otp_'.$user->phone);
        $this->assertNotNull($real);

        if ($real !== '123456') {
            $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
                ->assertStatus(422);
        }

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => $real])
            ->assertOk()->assertJsonStructure(['access_token']);
    }

    public function test_123456_no_longer_signs_a_partner_in_when_whatsapp_codes_are_on(): void
    {
        $this->liveWhatsAppOtp();
        $owner = $this->user('admin', 'o');

        $this->postJson('/api/partner/auth/send-otp', ['phone' => $owner->phone])->assertOk();
        $real = Cache::get('partner_otp_'.$owner->phone);

        if ($real !== '123456') {
            $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => '123456'])
                ->assertStatus(400);
        }

        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => $real])
            ->assertOk()->assertJsonPath('status', 'existing_user');
    }

    public function test_no_code_works_for_a_phone_that_was_never_sent_one(): void
    {
        $user = $this->user('customer', 'c');

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertStatus(422);
    }

    public function test_the_demo_code_still_works_when_whatsapp_codes_are_off(): void
    {
        $user = $this->user('customer', 'c');

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $user->phone])->assertOk();
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $user->phone, 'otp' => '123456'])
            ->assertOk()->assertJsonStructure(['access_token']);
    }

    public function test_five_wrong_codes_throw_the_code_away(): void
    {
        $owner = $this->user('admin', 'o');
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $owner->phone])->assertOk();

        foreach (range(1, 5) as $_) {
            $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => '000000'])
                ->assertStatus(400);
        }

        // Even the right code is refused now; a new one must be asked for.
        $this->postJson('/api/partner/auth/verify-otp', ['phone' => $owner->phone, 'otp' => '123456'])
            ->assertStatus(400);
    }

    public function test_a_review_number_signs_in_with_its_fixed_code_and_nothing_else_does(): void
    {
        $this->liveWhatsAppOtp();
        $reviewer = $this->user('customer', 'r');
        $other = $this->user('customer', 'x');
        config(['services.otp.review_phones' => ['+91 '.$reviewer->phone], 'services.otp.review_code' => '424242']);

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $reviewer->phone])->assertOk();
        $this->assertNull(Cache::get('otp_'.$reviewer->phone), 'a review number is never sent a code');

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $reviewer->phone, 'otp' => '424242'])
            ->assertOk()->assertJsonStructure(['access_token']);

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $other->phone])->assertOk();
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $other->phone, 'otp' => '424242'])
            ->assertStatus(422);
    }

    public function test_a_too_short_review_code_is_ignored(): void
    {
        $reviewer = $this->user('customer', 'r');
        config(['services.otp.review_phones' => [$reviewer->phone], 'services.otp.review_code' => '1']);

        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $reviewer->phone, 'otp' => '1'])->assertStatus(422);
    }

    public function test_asking_for_codes_is_rate_limited_per_phone(): void
    {
        $phone = $this->phone('p');

        foreach (range(1, 3) as $_) {
            $this->postJson('/api/partner/auth/send-otp', ['phone' => $phone])->assertOk();
        }
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $phone])
            ->assertStatus(429)->assertJsonStructure(['message']);

        // Another number is not held up.
        $this->postJson('/api/partner/auth/send-otp', ['phone' => $this->phone('q')])->assertOk();
    }

    public function test_superadmin_login_is_rate_limited(): void
    {
        $admin = $this->user('superadmin', 'sa');

        foreach (range(1, 5) as $_) {
            $this->postJson('/api/superadmin/auth/login', ['email' => $admin->email, 'password' => 'wrong'])
                ->assertStatus(401);
        }
        $this->postJson('/api/superadmin/auth/login', ['email' => $admin->email, 'password' => 'secret-password'])
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

    public function test_an_app_login_expires_after_ninety_days(): void
    {
        $owner = $this->user('admin', 'o');
        $token = $owner->createToken('partner-auth-token')->plainTextToken;

        $this->withToken($token)->getJson('/api/partner/auth/check')->assertOk();

        PersonalAccessToken::findToken($token)->forceFill(['created_at' => now()->subDays(91)])->save();
        $this->app['auth']->forgetGuards();

        $this->withToken($token)->getJson('/api/partner/auth/check')->assertStatus(401);
    }

    protected function tearDown(): void
    {
        RateLimiter::clear('otp-send');
        parent::tearDown();
    }
}
