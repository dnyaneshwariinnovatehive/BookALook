<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\SalonLinkService;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The printed QR code in a salon window.
 *
 * The least forgiving thing the platform produces: it goes on a wall, gets
 * laminated, and nobody reprints it. So the link is built in one place from an
 * address SuperAdmin can move, and it is always plain https — Google Lens and
 * the camera scanner follow http and https and silently ignore anything else.
 */
class SalonQrCodeTest extends TestCase
{
    use DatabaseTransactions;

    public function test_the_printed_link_is_plain_https_so_any_scanner_follows_it(): void
    {
        $this->givenWebAddress('https://bookalook.test');
        [$salon] = $this->givenSalon();

        $url = app(SalonLinkService::class)->publicUrl($salon->fresh());

        $this->assertStringStartsWith('https://bookalook.test/s/', $url);
        $this->assertStringContainsString($salon->slug, $url);
        // A custom scheme on a poster does nothing in a camera app.
        $this->assertStringNotContainsString('bookalook://', $url);
    }

    public function test_moving_the_site_redirects_every_poster_already_printed(): void
    {
        [$salon] = $this->givenSalon();

        $this->givenWebAddress('https://old.example');
        $before = app(SalonLinkService::class)->publicUrl($salon);

        $this->givenWebAddress('https://new.example');
        $after = app(SalonLinkService::class)->publicUrl($salon);

        // Same path, new host: the QR on the wall keeps working.
        $this->assertSame('https://old.example/s/' . $salon->slug, $before);
        $this->assertSame('https://new.example/s/' . $salon->slug, $after);
    }

    public function test_a_trailing_slash_does_not_produce_a_double_slash(): void
    {
        $this->givenWebAddress('https://bookalook.test/');
        [$salon] = $this->givenSalon();

        $this->assertSame(
            'https://bookalook.test/s/' . $salon->slug,
            app(SalonLinkService::class)->publicUrl($salon)
        );
    }

    public function test_the_landing_page_can_name_the_salon_without_an_account(): void
    {
        [$salon] = $this->givenSalon();

        // No token: whoever scanned the poster has no account yet, which is the
        // entire reason the poster exists.
        $body = $this->getJson("/api/public/salons/{$salon->slug}")
            ->assertStatus(200)
            ->json();

        $this->assertSame($salon->name, $body['salon']['name']);
        $this->assertTrue($body['salon']['is_bookable']);
        $this->assertSame("bookalook://salon/{$salon->id}", $body['deep_link']);
        $this->assertStringContainsString('intent://salon/', $body['android_intent_link']);
    }

    public function test_an_unknown_slug_is_a_clean_404_not_an_error(): void
    {
        $this->getJson('/api/public/salons/no-such-salon-anywhere')
            ->assertStatus(404)
            ->assertJsonPath('success', false);
    }

    public function test_a_lapsed_salon_still_gets_a_page_but_promises_nothing(): void
    {
        [$salon] = $this->givenSalon(bookable: false);

        $body = $this->getJson("/api/public/salons/{$salon->slug}")
            ->assertStatus(200)
            ->json();

        // Somebody is standing in front of it, so the page exists — it just
        // does not offer a booking it cannot take.
        $this->assertSame($salon->name, $body['salon']['name']);
        $this->assertFalse($body['salon']['is_bookable']);
    }

    public function test_a_store_button_is_hidden_until_the_listing_is_live(): void
    {
        $this->givenSetting('android_app_url', '');
        $this->givenSetting('ios_app_url', '');
        $this->givenSetting('android_apk_url', '');

        $links = $this->getJson('/api/public/app-links')->assertStatus(200)->json('app_links');

        // Sending somebody to a store page that does not exist yet is worse
        // than not offering the button at all.
        $this->assertFalse($links['has_android']);
        $this->assertFalse($links['has_ios']);
    }

    public function test_a_direct_build_counts_while_the_store_listing_does_not_exist(): void
    {
        $this->givenSetting('android_app_url', '');
        $this->givenSetting('android_apk_url', 'https://bookalook.test/app.apk');

        $links = $this->getJson('/api/public/app-links')->assertStatus(200)->json('app_links');

        $this->assertTrue($links['has_android']);
        $this->assertSame('https://bookalook.test/app.apk', $links['android_apk_url']);
    }

    public function test_superadmin_can_move_the_address_every_poster_points_at(): void
    {
        $superAdmin = User::where('role', 'superadmin')->firstOrFail();

        $this->actingAs($superAdmin, 'sanctum')
            ->putJson('/api/superadmin/settings/policy', [
                'public_web_url' => 'https://moved.example/',
                'android_app_url' => 'https://play.google.com/store/apps/details?id=x',
            ])
            ->assertStatus(200);

        // Stored without the trailing slash, so joining a path stays clean.
        $this->assertSame('https://moved.example', PlatformPolicySetting::value('public_web_url'));
        $this->assertTrue(
            $this->getJson('/api/public/app-links')->json('app_links.has_android')
        );
    }

    public function test_an_owner_gets_their_own_qr_link_and_nobody_elses(): void
    {
        $this->givenWebAddress('https://bookalook.test');

        [$salon, $owner] = $this->givenSalon();
        [$other] = $this->givenSalon();

        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/qr-code")
            ->assertStatus(200)
            ->assertJsonPath('url', "https://bookalook.test/s/{$salon->slug}")
            ->assertJsonPath('salon_name', $salon->name);

        // Another owner's poster is not theirs to print.
        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$other->id}/qr-code")
            ->assertStatus(404);
    }

    // ----------------------------------------------------------------- setup

    private function givenWebAddress(string $url): void
    {
        $this->givenSetting('public_web_url', $url);
    }

    private function givenSetting(string $key, string $value): void
    {
        PlatformPolicySetting::updateOrCreate(
            ['setting_key' => $key],
            [
                'setting_value' => $value,
                'data_type' => 'string',
                'description' => 'test',
                'updated_by' => User::where('role', 'superadmin')->value('id'),
            ]
        );
    }

    /** @return array{0: Salon, 1: User} */
    private function givenSalon(bool $bookable = true): array
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $owner = User::create([
            'name' => "Owner {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $owner->id,
            'name' => "QR Salon {$unique}",
            'slug' => "qr-salon-{$unique}",
            'address' => 'Test address',
            'city_id' => City::where('is_active', true)->value('id'),
            'submitted_by' => $owner->id,
            'status' => 'active',
        ]);

        $plan = SubscriptionPlan::first();

        if ($plan) {
            SalonSubscription::create([
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => BillingModel::SUBSCRIPTION,
                'plan_price_snapshot' => $plan->price,
                'start_date' => Carbon::today()->subDays(10),
                // A lapsed plan is what makes a salon unbookable while its
                // poster is still on the wall.
                'end_date' => $bookable ? Carbon::today()->addDays(20) : Carbon::yesterday(),
                'status' => $bookable ? 'active' : 'expired',
            ]);
        }

        return [$salon, $owner];
    }
}
