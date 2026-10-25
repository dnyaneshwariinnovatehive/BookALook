<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Anyone signed in can move their account to a new phone number, once they
 * prove they hold it. The new number then signs them in; the old one does not.
 */
class PhoneChangeTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();
        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
        Cache::flush();
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
            'password_hash' => bcrypt('password'),
            'is_active' => true,
        ]);
    }

    private function urls(string $role): array
    {
        return $role === 'customer'
            ? ['/api/customer/profile/phone/send-otp', '/api/customer/profile/phone/verify']
            : ['/api/partner/me/phone/send-otp', '/api/partner/me/phone/verify'];
    }

    public static function roles(): array
    {
        return [['customer'], ['admin'], ['service_provider'], ['collaborator']];
    }

    /** @dataProvider roles */
    public function test_every_kind_of_user_can_change_their_number(string $role): void
    {
        $user = $this->user($role, 'me');
        $new = $this->phone("new-{$role}");
        [$send, $verify] = $this->urls($role);

        $this->actingAs($user, 'sanctum')->postJson($send, ['phone' => $new])->assertStatus(200);
        $this->actingAs($user, 'sanctum')->postJson($verify, ['phone' => $new, 'otp' => '123456'])
            ->assertStatus(200)
            ->assertJsonPath('user.phone', $new);

        $this->assertDatabaseHas('users', ['id' => $user->id, 'phone' => $new]);
    }

    public function test_the_new_number_signs_in_afterwards(): void
    {
        $user = $this->user('customer', 'me');
        $old = $user->phone;
        $new = $this->phone('new');

        $this->actingAs($user, 'sanctum')->postJson('/api/customer/profile/phone/send-otp', ['phone' => $new]);
        $this->actingAs($user, 'sanctum')->postJson('/api/customer/profile/phone/verify', ['phone' => $new, 'otp' => '123456'])->assertStatus(200);

        $this->postJson('/api/customer/auth/send-otp', ['phone' => $new]);
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => $new, 'otp' => '123456'])
            ->assertStatus(200)
            ->assertJsonStructure(['access_token']);

        $this->assertNull(User::where('phone', $old)->first());
    }

    public function test_spaces_and_dashes_are_cleaned_up(): void
    {
        $user = $this->user('admin', 'me');
        $new = $this->phone('new');
        $typed = substr($new, 0, 5).' '.substr($new, 5, 3).'-'.substr($new, 8);

        $this->actingAs($user, 'sanctum')->postJson('/api/partner/me/phone/send-otp', ['phone' => $typed])->assertStatus(200);
        $this->actingAs($user, 'sanctum')->postJson('/api/partner/me/phone/verify', ['phone' => $typed, 'otp' => '123456'])->assertStatus(200);

        $this->assertSame($new, $user->fresh()->phone);
    }

    public function test_a_wrong_code_changes_nothing_and_five_wrong_codes_burn_it(): void
    {
        $user = $this->user('customer', 'me');
        $old = $user->phone;
        $new = $this->phone('new');

        $this->actingAs($user, 'sanctum')->postJson('/api/customer/profile/phone/send-otp', ['phone' => $new]);

        for ($i = 0; $i < 5; $i++) {
            $this->actingAs($user, 'sanctum')
                ->postJson('/api/customer/profile/phone/verify', ['phone' => $new, 'otp' => '000000'])
                ->assertStatus(422)
                ->assertJsonValidationErrors('otp');
        }

        // Even the right code is no good now.
        $this->actingAs($user, 'sanctum')
            ->postJson('/api/customer/profile/phone/verify', ['phone' => $new, 'otp' => '123456'])
            ->assertStatus(422);

        $this->assertSame($old, $user->fresh()->phone);
    }

    public function test_a_code_only_works_for_the_number_it_was_sent_to(): void
    {
        $user = $this->user('customer', 'me');
        $this->actingAs($user, 'sanctum')->postJson('/api/customer/profile/phone/send-otp', ['phone' => $this->phone('a')]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/customer/profile/phone/verify', ['phone' => $this->phone('b'), 'otp' => '123456'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('otp');
    }

    public function test_cannot_take_a_number_another_account_uses(): void
    {
        $user = $this->user('customer', 'me');
        $other = $this->user('admin', 'other');

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/customer/profile/phone/send-otp', ['phone' => $other->phone])
            ->assertStatus(422)
            ->assertJsonValidationErrors('phone');
    }

    public function test_number_taken_between_sending_and_confirming_is_refused(): void
    {
        $user = $this->user('customer', 'me');
        $new = $this->phone('new');
        $this->actingAs($user, 'sanctum')->postJson('/api/customer/profile/phone/send-otp', ['phone' => $new])->assertStatus(200);

        $this->user('admin', 'sniper')->update(['phone' => $new]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/customer/profile/phone/verify', ['phone' => $new, 'otp' => '123456'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('phone');
    }

    public function test_rejects_own_number_and_nonsense(): void
    {
        $user = $this->user('service_provider', 'me');

        $this->actingAs($user, 'sanctum')->postJson('/api/partner/me/phone/send-otp', ['phone' => $user->phone])
            ->assertStatus(422);
        $this->actingAs($user, 'sanctum')->postJson('/api/partner/me/phone/send-otp', ['phone' => '12ab'])
            ->assertStatus(422);
    }

    public function test_profile_update_no_longer_changes_the_number_unverified(): void
    {
        $user = $this->user('customer', 'me');
        $old = $user->phone;

        $this->actingAs($user, 'sanctum')
            ->putJson('/api/customer/profile/update', ['name' => 'Renamed', 'phone' => $this->phone('sneaky')])
            ->assertStatus(422);
        $this->assertSame($old, $user->fresh()->phone);

        // Sending the current number back, as the edit form does, still works.
        $this->actingAs($user, 'sanctum')
            ->putJson('/api/customer/profile/update', ['name' => 'Renamed', 'phone' => $old])
            ->assertStatus(200);
        $this->assertSame('Renamed', $user->fresh()->name);
    }

    public function test_requires_sign_in(): void
    {
        $this->postJson('/api/customer/profile/phone/send-otp', ['phone' => $this->phone('x')])->assertStatus(401);
        $this->postJson('/api/partner/me/phone/send-otp', ['phone' => $this->phone('x')])->assertStatus(401);
    }
}
