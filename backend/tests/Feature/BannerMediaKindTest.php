<?php

namespace Tests\Feature;

use App\Models\Banner;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The media axis of a banner: is image_url a static raster (JPG/PNG) or an
 * animated one (GIF/WebP)?
 *
 * `media_kind` is deliberately separate from banner_type — a seasonal banner
 * can carry an animated WebP just as a static one can. The backend only has to
 * keep the two axes honest: an animated banner needs an image, the extension
 * has to exist in the allow-list, and the kind has to match the extension.
 *
 * Runs in a transaction so it can use the development database without leaving
 * anything behind.
 */
class BannerMediaKindTest extends TestCase
{
    use DatabaseTransactions;

    // ------------------------------------------------------------- store

    public function test_media_kind_defaults_to_image_when_omitted(): void
    {
        $response = $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url' => $this->url('poster.jpg'),
        ]));

        $response->assertStatus(201);
        $this->assertSame('image', $response->json('banner.media_kind'));
    }

    public function test_an_animated_banner_is_stored_as_animated(): void
    {
        $response = $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url'  => $this->url('sale-loop.gif'),
            'media_kind' => 'animated',
        ]));

        $response->assertStatus(201);
        $this->assertSame('animated', $response->json('banner.media_kind'));
        $this->assertSame('animated', Banner::findOrFail($response->json('banner.id'))->media_kind);
    }

    public function test_an_animated_webp_is_accepted(): void
    {
        $response = $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url'  => $this->url('hero.webp'),
            'media_kind' => 'animated',
        ]));

        $response->assertStatus(201);
        $this->assertSame('animated', $response->json('banner.media_kind'));
    }

    public function test_an_unknown_media_kind_is_rejected_by_validation(): void
    {
        $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url'  => $this->url('poster.jpg'),
            'media_kind' => 'video',
        ]))->assertStatus(422)->assertJsonValidationErrors('media_kind');
    }

    // -------------------------------------------------- consistency rules

    public function test_an_animated_banner_without_an_image_is_rejected(): void
    {
        // banner_type seasonal (not static) so the "static requires an image"
        // rule does not fire first and mask the media check under test.
        $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'banner_type' => 'seasonal',
            'media_kind'  => 'animated',
        ]))->assertStatus(422)->assertJson(['message' => 'Animated banners require an image URL.']);
    }

    public function test_an_animated_banner_pointing_at_a_jpeg_is_rejected(): void
    {
        $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url'  => $this->url('poster.jpg'),
            'media_kind' => 'animated',
        ]))->assertStatus(422)->assertJsonFragment([
            'message' => 'media_kind "animated" requires a GIF or WebP image, got "jpg".',
        ]);
    }

    public function test_a_gif_url_without_media_kind_is_told_to_declare_it(): void
    {
        // New writes must be explicit: a GIF URL defaults to media_kind image,
        // which the extension check then refuses with a pointer to the fix.
        $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url' => $this->url('sale-loop.gif'),
        ]))->assertStatus(422)->assertJsonFragment([
            'message' => 'The image at that URL is not a static JPG or PNG. '
                .'If it is a GIF or animated WebP, send media_kind: "animated".',
        ]);
    }

    public function test_an_image_banner_pointing_at_a_gif_with_media_kind_image_is_rejected(): void
    {
        $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url'  => $this->url('sale-loop.gif'),
            'media_kind' => 'image',
        ]))->assertStatus(422);
    }

    public function test_formats_outside_the_allow_list_are_rejected(): void
    {
        foreach (['poster.svg', 'clip.mp4', 'clip.webm', 'anim.json'] as $bad) {
            $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
                'image_url'  => $this->url($bad),
                'media_kind' => 'animated',
            ]))->assertStatus(422)->assertJsonFragment([
                'message' => sprintf('Unsupported image format "%s". Allowed formats: jpg, jpeg, png, gif, webp.', pathinfo($bad, PATHINFO_EXTENSION)),
            ]);
        }
    }

    public function test_a_static_banner_still_requires_an_image(): void
    {
        // The original rule keeps precedence over the media checks.
        $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'media_kind' => 'image',
        ]))->assertStatus(422)->assertJson(['message' => 'Static banners require an image.']);
    }

    public function test_extensionless_urls_skip_the_extension_checks(): void
    {
        // Cloudinary transform URLs (…/image/upload/v123/abc) carry no file
        // extension, so the media check stays lenient rather than blocking them.
        $response = $this->superAdmin()->postJson('/api/superadmin/banners', $this->payload([
            'image_url'  => 'https://res.cloudinary.com/demo/image/upload/v123456/banner-assets/sale',
            'media_kind' => 'animated',
        ]));

        $response->assertStatus(201);
        $this->assertSame('animated', $response->json('banner.media_kind'));
    }

    // ------------------------------------------------------------- update

    public function test_a_static_banner_can_be_switched_to_animated_on_edit(): void
    {
        $banner = $this->banner(['image_url' => $this->url('poster.jpg'), 'media_kind' => 'image']);

        $response = $this->superAdmin()->putJson("/api/superadmin/banners/{$banner->id}", [
            'image_url'  => $this->url('sale-loop.gif'),
            'media_kind' => 'animated',
        ]);

        $response->assertStatus(200);
        $this->assertSame('animated', $banner->fresh()->media_kind);
    }

    public function test_editing_an_unrelated_field_on_a_legacy_gif_row_does_not_conflict(): void
    {
        // A GIF row that predates media_kind (stored as the 'image' default)
        // must still accept a partial update that leaves the image alone.
        $banner = $this->banner(['image_url' => $this->url('old-loop.gif'), 'media_kind' => 'image']);

        $this->superAdmin()->putJson("/api/superadmin/banners/{$banner->id}", [
            'title' => 'Renamed without touching media',
        ])->assertStatus(200);

        $banner->refresh();
        $this->assertSame('old-loop.gif', basename((string) $banner->image_url));
        $this->assertSame('image', $banner->media_kind);
    }

    public function test_editing_cannot_point_an_animated_banner_at_a_jpeg(): void
    {
        $banner = $this->banner(['image_url' => $this->url('sale-loop.gif'), 'media_kind' => 'animated']);

        $this->superAdmin()->putJson("/api/superadmin/banners/{$banner->id}", [
            'image_url' => $this->url('poster.jpg'),
        ])->assertStatus(422);

        $this->assertSame('sale-loop.gif', basename((string) $banner->fresh()->image_url));
    }

    // ---------------------------------------------------------- responses

    public function test_superadmin_and_customer_payloads_both_carry_media_kind(): void
    {
        $banner = $this->banner([
            'image_url'   => $this->url('sale-loop.gif'),
            'media_kind'  => 'animated',
            'start_date'  => now()->subDay()->toDateString(),
            'end_date'    => now()->addDay()->toDateString(),
            'is_active'   => true,
            'target_scope' => 'platform',
        ]);

        $this->superAdmin()
            ->getJson('/api/superadmin/banners')
            ->assertOk()
            ->assertJsonFragment(['id' => $banner->id, 'media_kind' => 'animated']);

        $this->getJson('/api/customer/banners')
            ->assertOk()
            ->assertJsonFragment(['id' => $banner->id, 'media_kind' => 'animated']);
    }

    public function test_the_customer_list_never_returns_an_empty_image_url(): void
    {
        // PromoBanner.fromJson treats image_url as non-nullable; one null would
        // take down the whole carousel, so any leftover empty row is filled in.
        $id = $this->insertRawBanner([
            'title'       => 'No image yet',
            'banner_type' => 'static',
            'image_url'   => '',
        ]);

        $response = $this->getJson('/api/customer/banners')->assertOk();

        $row = collect($response->json())->firstWhere('id', $id);
        $this->assertNotNull($row, 'the placeholder-less banner should still be listed');
        $this->assertNotEmpty($row['image_url']);
        $this->assertStringStartsWith('https://via.placeholder.com/', $row['image_url']);
    }

    public function test_the_customer_list_leaves_banners_that_already_have_an_image_alone(): void
    {
        $id = $this->insertRawBanner([
            'title'       => 'Has an image',
            'banner_type' => 'static',
            'image_url'   => $this->url('poster.jpg'),
        ]);

        $row = collect($this->getJson('/api/customer/banners')->assertOk()->json())
            ->firstWhere('id', $id);

        $this->assertSame($this->url('poster.jpg'), $row['image_url']);
    }

    // ----------------------------------------------------------- helpers

    private function superAdmin()
    {
        $user = User::firstOrCreate(
            ['phone' => '9000000001'],
            [
                'role'          => 'superadmin',
                'name'          => 'Banner Media SuperAdmin',
                'password_hash' => bcrypt('secret'),
            ]
        );

        return $this->actingAs($user, 'sanctum');
    }

    /** Valid store payload; callers override the media fields under test. */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'title'        => 'Media kind banner',
            'banner_type'  => 'static',
            'image_url'    => null,
            'target_scope' => 'platform',
            'start_date'   => now()->subDay()->toDateString(),
            'end_date'     => now()->addDay()->toDateString(),
            'is_active'    => true,
        ], $overrides);
    }

    private function banner(array $attributes = []): Banner
    {
        return Banner::create(array_merge([
            'title'        => 'Existing banner',
            'banner_type'  => 'static',
            'target_scope' => 'platform',
            'start_date'   => now()->subDay(),
            'end_date'     => now()->addDay(),
            'is_active'    => true,
        ], $attributes));
    }

    /**
     * Insert straight through the query builder so the test can create rows the
     * API itself would not (empty image_url), exactly as a legacy row might sit.
     */
    private function insertRawBanner(array $overrides = []): string
    {
        $id = (string) \Illuminate\Support\Str::uuid();

        DB::table('banners')->insert(array_merge([
            'id'           => $id,
            'title'        => 'Raw banner',
            'banner_type'  => 'static',
            'media_kind'   => 'image',
            'image_url'    => $this->url('poster.jpg'),
            'action_url'   => null,
            'target_scope' => 'platform',
            'start_date'   => now()->subDay()->toDateString(),
            'end_date'     => now()->addDay()->toDateString(),
            'is_active'    => true,
            'priority'     => 0,
            'impressions'  => 0,
            'clicks'       => 0,
            'created_at'   => now(),
            'updated_at'   => now(),
        ], $overrides));

        return $id;
    }

    private function url(string $file): string
    {
        return 'https://res.cloudinary.com/demo/image/upload/v123456/banners/'.$file;
    }
}
