<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\ProviderWorkingHour;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Support\GenderFocus;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Gender is set once on the template by the superadmin, a salon may only
 * narrow a Unisex template, customers browse services meant for them, and a
 * booking can be for someone other than the account holder.
 */
class GenderAwareServicesTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;
    private User $superadmin;
    private User $customer;
    private ServiceCategory $category;
    private ServiceTemplate $mensCut;
    private ServiceTemplate $womensCut;
    private ServiceTemplate $headMassage;
    private \App\Models\City $city;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->city = \App\Models\City::create(['name' => "Gendertown {$this->unique}", 'state' => 'MH', 'is_active' => true]);
        $this->superadmin = $this->makeUser('superadmin', 'sa');
        $this->customer = $this->makeUser('customer', 'cu', 'female');

        $this->category = ServiceCategory::create([
            'name' => "Hair {$this->unique}",
            'is_custom' => false,
            'is_active' => true,
        ]);

        $this->mensCut = $this->makeTemplate("Men's Cut {$this->unique}", GenderFocus::MEN);
        $this->womensCut = $this->makeTemplate("Women's Cut {$this->unique}", GenderFocus::WOMEN);
        $this->headMassage = $this->makeTemplate("Head Massage {$this->unique}", GenderFocus::UNISEX);
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private function makeUser(string $role, string $tag, string $gender = 'unspecified'): User
    {
        return User::create([
            'id' => (string) Str::uuid(),
            'name' => "{$role} {$this->unique}",
            'phone' => '8'.substr((string) crc32($this->unique.$tag), 0, 9),
            'password_hash' => bcrypt('password'),
            'role' => $role,
            'gender' => $gender,
            'is_active' => true,
        ]);
    }

    private function makeTemplate(string $name, string $gender): ServiceTemplate
    {
        return ServiceTemplate::create([
            'category_id' => $this->category->id,
            'name' => $name,
            'estimated_duration_minutes' => 30,
            'gender_focus' => $gender,
            'is_custom' => false,
            'is_active' => true,
        ]);
    }

    /** @return array{0: User, 1: Salon} */
    private function makeSalon(string $focus, string $tag): array
    {
        $owner = $this->makeUser('admin', "own{$tag}");

        $salon = Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $owner->id,
            'name' => "Salon {$tag} {$this->unique}",
            'slug' => "salon-{$tag}-{$this->unique}",
            'address' => '1 Gender Street',
            'submitted_by' => $owner->id,
            'status' => 'active',
            'gender_focus' => $focus,
            'city_id' => $this->city->id,
        ]);

        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Growth Plan',
            'price' => 999.00,
            'duration_days' => 30,
            'is_active' => true,
        ]);

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => now()->subDays(5)->toDateString(),
            'end_date' => now()->addDays(25)->toDateString(),
            'status' => 'active',
        ]);

        return [$owner, $salon];
    }

    private function offer(Salon $salon, ServiceTemplate $template, ?string $gender = null): Service
    {
        return Service::create([
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => 300,
            'gender_focus' => $gender ?? $template->gender_focus,
            'is_active' => true,
        ]);
    }

    private function add(Salon $salon, array $body)
    {
        return $this->postJson("/api/partner/salons/{$salon->id}/services", $body + ['price' => 400]);
    }

    // ── The rules themselves ──────────────────────────────────────────────

    public function test_rules_lock_gendered_templates_and_let_salons_narrow_unisex(): void
    {
        $this->assertSame([GenderFocus::MEN], GenderFocus::allowedFor(GenderFocus::MEN, GenderFocus::UNISEX));
        $this->assertSame([GenderFocus::MEN], GenderFocus::allowedFor(GenderFocus::MEN, GenderFocus::MEN));
        $this->assertSame([], GenderFocus::allowedFor(GenderFocus::MEN, GenderFocus::WOMEN));
        $this->assertSame(GenderFocus::ALL, GenderFocus::allowedFor(GenderFocus::UNISEX, GenderFocus::UNISEX));
        $this->assertSame([GenderFocus::WOMEN], GenderFocus::allowedFor(GenderFocus::UNISEX, GenderFocus::WOMEN));

        $this->assertSame(GenderFocus::WOMEN, GenderFocus::effective(GenderFocus::UNISEX, GenderFocus::WOMEN));
        $this->assertSame(GenderFocus::MEN, GenderFocus::effective(GenderFocus::MEN, GenderFocus::UNISEX));

        $this->assertSame(GenderFocus::MEN, GenderFocus::suggestFromName("Men's Haircut"));
        $this->assertSame(GenderFocus::WOMEN, GenderFocus::suggestFromName("Women's Haircut"));
        $this->assertSame(GenderFocus::MEN, GenderFocus::suggestFromName('Beard Trim'));
        $this->assertNull(GenderFocus::suggestFromName('Gentle Facial'));
        $this->assertNull(GenderFocus::suggestFromName('Head Massage'));
    }

    // ── Superadmin sets gender on the template ────────────────────────────

    public function test_superadmin_creates_templates_with_a_gender(): void
    {
        Sanctum::actingAs($this->superadmin);

        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => $this->category->id,
            'name' => 'Beard Sculpt',
            'estimated_duration_minutes' => 30,
            'gender_focus' => GenderFocus::MEN,
        ])->assertStatus(200)->assertJsonPath('template.gender_focus', GenderFocus::MEN);

        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => $this->category->id,
            'name' => 'Scalp Detox',
            'estimated_duration_minutes' => 30,
        ])->assertStatus(200)->assertJsonPath('template.gender_focus', GenderFocus::UNISEX);

        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => $this->category->id,
            'name' => 'Bad',
            'estimated_duration_minutes' => 30,
            'gender_focus' => 'Kids',
        ])->assertStatus(422);
    }

    public function test_making_a_template_gendered_brings_every_salon_along(): void
    {
        [, $unisexSalon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        [, $womenSalon] = $this->makeSalon(GenderFocus::WOMEN, 'w');
        $template = $this->makeTemplate("Threading {$this->unique}", GenderFocus::UNISEX);

        $kept = $this->offer($unisexSalon, $template, GenderFocus::UNISEX);
        $deleted = $this->offer($womenSalon, $template, GenderFocus::WOMEN);
        $deleted->delete();

        Sanctum::actingAs($this->superadmin);

        $this->putJson("/api/superadmin/catalog/templates/{$template->id}", [
            'name' => $template->name,
            'estimated_duration_minutes' => 30,
            'gender_focus' => GenderFocus::WOMEN,
        ])->assertStatus(200)
            ->assertJsonPath('template.gender_focus', GenderFocus::WOMEN)
            ->assertJsonPath('services_updated', 1)
            ->assertJsonPath('salon_conflicts', 0);

        $this->assertSame(GenderFocus::WOMEN, $kept->fresh()->gender_focus);
        $this->assertSame(GenderFocus::WOMEN, Service::withTrashed()->find($deleted->id)->gender_focus);
    }

    public function test_gender_change_reports_salons_of_the_other_gender(): void
    {
        [, $menSalon] = $this->makeSalon(GenderFocus::MEN, 'm');
        $template = $this->makeTemplate("Facial {$this->unique}", GenderFocus::UNISEX);
        $this->offer($menSalon, $template, GenderFocus::MEN);

        Sanctum::actingAs($this->superadmin);

        $this->putJson("/api/superadmin/catalog/templates/{$template->id}", [
            'name' => $template->name,
            'estimated_duration_minutes' => 30,
            'gender_focus' => GenderFocus::WOMEN,
        ])->assertStatus(200)->assertJsonPath('salon_conflicts', 1);
    }

    public function test_going_back_to_unisex_keeps_salons_narrowing(): void
    {
        [, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        $service = $this->offer($salon, $this->mensCut, GenderFocus::MEN);

        Sanctum::actingAs($this->superadmin);

        $this->putJson("/api/superadmin/catalog/templates/{$this->mensCut->id}", [
            'name' => $this->mensCut->name,
            'estimated_duration_minutes' => 30,
            'gender_focus' => GenderFocus::UNISEX,
        ])->assertStatus(200)->assertJsonPath('services_updated', 0);

        $this->assertSame(GenderFocus::MEN, $service->fresh()->gender_focus);
    }

    public function test_catalog_reports_salon_tagging_and_name_suggestions(): void
    {
        [, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        $misfiled = $this->makeTemplate("Ladies Cut {$this->unique}", GenderFocus::UNISEX);
        $this->offer($salon, $misfiled, GenderFocus::WOMEN);
        $this->offer($salon, $this->headMassage, GenderFocus::UNISEX);

        Sanctum::actingAs($this->superadmin);

        $templates = collect($this->getJson('/api/superadmin/catalog')->assertStatus(200)->json('categories'))
            ->firstWhere('id', $this->category->id)['templates'];
        $byId = collect($templates)->keyBy('id');

        $this->assertSame(GenderFocus::WOMEN, $byId[$misfiled->id]['suggested_gender_focus']);
        $this->assertSame(1, $byId[$misfiled->id]['salon_gender_counts'][GenderFocus::WOMEN]);
        $this->assertNull($byId[$this->headMassage->id]['suggested_gender_focus']);
        $this->assertNull($byId[$this->mensCut->id]['suggested_gender_focus']);
    }

    // ── Salons can only narrow ────────────────────────────────────────────

    public function test_partner_catalog_hides_templates_the_salon_cannot_offer(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::WOMEN, 'w');
        Sanctum::actingAs($owner);

        $response = $this->getJson("/api/partner/salons/{$salon->id}/master-catalog")->assertStatus(200);
        $templates = collect(collect($response->json('categories'))->firstWhere('id', $this->category->id)['templates'])->keyBy('id');

        $this->assertFalse($templates->has($this->mensCut->id));
        $this->assertSame([GenderFocus::WOMEN], $templates[$this->womensCut->id]['allowed_gender_focus']);
        $this->assertSame([GenderFocus::WOMEN], $templates[$this->headMassage->id]['allowed_gender_focus']);
        $response->assertJsonPath('salon_gender_focus', GenderFocus::WOMEN);
        $response->assertJsonPath('custom_allowed_gender_focus', [GenderFocus::WOMEN]);
    }

    public function test_gendered_template_is_locked_to_its_gender(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        Sanctum::actingAs($owner);

        $this->add($salon, ['is_custom' => false, 'template_id' => $this->mensCut->id, 'gender_focus' => GenderFocus::WOMEN])
            ->assertStatus(422)->assertJsonPath('allowed_gender_focus', [GenderFocus::MEN]);
        $this->add($salon, ['is_custom' => false, 'template_id' => $this->mensCut->id, 'gender_focus' => GenderFocus::UNISEX])
            ->assertStatus(422);

        $this->add($salon, ['is_custom' => false, 'template_id' => $this->mensCut->id])
            ->assertStatus(200)->assertJsonPath('service.gender_focus', GenderFocus::MEN);
    }

    public function test_unisex_template_can_be_narrowed_by_a_unisex_salon(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        Sanctum::actingAs($owner);

        $this->add($salon, ['is_custom' => false, 'template_id' => $this->headMassage->id, 'gender_focus' => GenderFocus::MEN])
            ->assertStatus(200)->assertJsonPath('service.gender_focus', GenderFocus::MEN);
    }

    public function test_single_gender_salon_caps_its_services(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::WOMEN, 'w');
        Sanctum::actingAs($owner);

        $this->add($salon, ['is_custom' => false, 'template_id' => $this->mensCut->id])
            ->assertStatus(422)->assertJsonPath('allowed_gender_focus', []);
        $this->add($salon, ['is_custom' => false, 'template_id' => $this->headMassage->id, 'gender_focus' => GenderFocus::MEN])
            ->assertStatus(422);

        // Left unsaid, a Unisex template in a Women Only salon is for women.
        $this->add($salon, ['is_custom' => false, 'template_id' => $this->headMassage->id])
            ->assertStatus(200)->assertJsonPath('service.gender_focus', GenderFocus::WOMEN);
    }

    public function test_custom_template_takes_the_gender_the_salon_chose(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        Sanctum::actingAs($owner);

        $this->add($salon, [
            'is_custom' => true,
            'category_id' => $this->category->id,
            'custom_template_name' => "Groom Package {$this->unique}",
            'estimated_duration_minutes' => 60,
            'gender_focus' => GenderFocus::MEN,
        ])->assertStatus(200)->assertJsonPath('service.gender_focus', GenderFocus::MEN);

        $this->assertDatabaseHas('service_templates', [
            'name' => "Groom Package {$this->unique}",
            'gender_focus' => GenderFocus::MEN,
            'created_by_salon_id' => $salon->id,
        ]);
    }

    public function test_editing_a_service_follows_the_same_rules(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        $locked = $this->offer($salon, $this->mensCut);
        $open = $this->offer($salon, $this->headMassage);
        Sanctum::actingAs($owner);

        $this->putJson("/api/partner/salons/{$salon->id}/services/{$locked->id}", ['gender_focus' => GenderFocus::WOMEN])
            ->assertStatus(422);
        $this->putJson("/api/partner/salons/{$salon->id}/services/{$open->id}", ['gender_focus' => GenderFocus::WOMEN])
            ->assertStatus(200);

        $this->assertSame(GenderFocus::MEN, $locked->fresh()->gender_focus);
        $this->assertSame(GenderFocus::WOMEN, $open->fresh()->gender_focus);
    }

    public function test_salon_cannot_switch_gender_while_offering_the_other_genders_services(): void
    {
        [$owner, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        $this->offer($salon, $this->mensCut);
        Sanctum::actingAs($owner);

        $this->putJson("/api/partner/salons/{$salon->id}", [
            'name' => $salon->name,
            'gender_focus' => GenderFocus::WOMEN,
        ])->assertStatus(422)->assertJsonPath('conflicting_services', [$this->mensCut->name]);

        $this->putJson("/api/partner/salons/{$salon->id}", [
            'name' => $salon->name,
            'gender_focus' => GenderFocus::MEN,
        ])->assertStatus(200);

        $this->putJson("/api/partner/salons/{$salon->id}", [
            'name' => $salon->name,
            'gender_focus' => 'Everyone',
        ])->assertStatus(422);
    }

    // ── Customers see what is meant for them ──────────────────────────────

    public function test_category_strip_only_shows_services_for_the_audience(): void
    {
        [, $unisexSalon] = $this->makeSalon(GenderFocus::UNISEX, 'u');
        [, $menSalon] = $this->makeSalon(GenderFocus::MEN, 'm');
        $this->offer($unisexSalon, $this->mensCut);
        $this->offer($unisexSalon, $this->womensCut);
        $this->offer($menSalon, $this->headMassage, GenderFocus::UNISEX);

        $names = fn (string $query) => collect(
            $this->getJson("/api/customer/categories/{$this->category->id}/services?city_id={$this->city->id}{$query}")->assertStatus(200)->json('services')
        )->pluck('name');

        $forWomen = $names('&gender=women');
        $this->assertTrue($forWomen->contains($this->womensCut->name));
        $this->assertFalse($forWomen->contains($this->mensCut->name));
        // Unisex on paper, but only at a Men Only salon.
        $this->assertFalse($forWomen->contains($this->headMassage->name));

        $everyone = $names('');
        $this->assertTrue($everyone->contains($this->mensCut->name));
        $this->assertTrue($everyone->contains($this->womensCut->name));
    }

    public function test_salon_list_by_category_skips_salons_with_nothing_for_her(): void
    {
        [, $beardOnly] = $this->makeSalon(GenderFocus::UNISEX, 'b');
        [, $forHer] = $this->makeSalon(GenderFocus::UNISEX, 'h');
        $this->offer($beardOnly, $this->mensCut);
        $this->offer($forHer, $this->womensCut);

        $ids = collect(
            $this->getJson("/api/customer/salons?city_id={$this->city->id}&category_id={$this->category->id}&gender=women")->assertStatus(200)->json('salons')
        )->pluck('id');

        $this->assertTrue($ids->contains($forHer->id));
        $this->assertFalse($ids->contains($beardOnly->id));
    }

    public function test_salon_page_says_who_each_service_is_for(): void
    {
        [, $womenSalon] = $this->makeSalon(GenderFocus::WOMEN, 'w');
        $this->offer($womenSalon, $this->headMassage, GenderFocus::UNISEX);

        $service = collect($this->getJson("/api/customer/salons/{$womenSalon->id}")->assertStatus(200)->json('salon.services'))->first();

        $this->assertSame(GenderFocus::UNISEX, $service['gender_focus']);
        $this->assertSame(GenderFocus::WOMEN, $service['audience']);
    }

    // ── Booking for someone else ──────────────────────────────────────────

    /** @return array{0: Salon, 1: ServiceProvider, 2: string, 3: string} */
    private function readyToBook(ServiceTemplate $template): array
    {
        [, $salon] = $this->makeSalon(GenderFocus::UNISEX, 'bk');

        for ($d = 0; $d <= 6; $d++) {
            SalonWorkingHour::create([
                'salon_id' => $salon->id,
                'day_of_week' => $d,
                'open_time' => '09:00:00',
                'close_time' => '19:00:00',
                'is_closed' => false,
            ]);
        }

        $provider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $this->makeUser('service_provider', 'pr')->id,
            'salon_id' => $salon->id,
            'is_active' => true,
        ]);

        for ($d = 0; $d <= 6; $d++) {
            ProviderWorkingHour::create([
                'provider_id' => $provider->id,
                'day_of_week' => $d,
                'shift_start' => '09:00:00',
                'shift_end' => '19:00:00',
                'is_weekly_off' => false,
            ]);
        }

        $service = $this->offer($salon, $template);
        $service->update(['advance_percentage' => 20]);
        $provider->services()->attach($service->id);

        Cart::where('customer_id', $this->customer->id)->where('status', 'active')->delete();
        $cart = Cart::create(['customer_id' => $this->customer->id, 'salon_id' => $salon->id, 'status' => 'active']);
        CartItem::create(['cart_id' => $cart->id, 'service_id' => $service->id, 'quantity' => 1]);

        for ($i = 1; $i <= 10; $i++) {
            $date = Carbon::today()->addDays($i)->toDateString();
            $slots = $this->actingAs($this->customer, 'sanctum')
                ->getJson("/api/customer/salons/{$salon->id}/availability?date={$date}&provider_id={$provider->id}")
                ->json('slots') ?? [];

            foreach ($slots as $slot) {
                if ($slot['available']) {
                    return [$salon, $provider, $date, $slot['time']];
                }
            }
        }

        $this->markTestSkipped('needs a day with a free slot');
    }

    public function test_cart_lines_say_who_they_are_for(): void
    {
        [$salon] = $this->readyToBook($this->mensCut);

        $items = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$salon->id}/cart")
            ->assertStatus(200)
            ->json('cart.items');

        $this->assertSame(GenderFocus::MEN, $items[0]['audience']);
    }

    public function test_booking_for_someone_else_records_who_is_in_the_chair(): void
    {
        [$salon, $provider, $date, $time] = $this->readyToBook($this->mensCut);

        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$salon->id}/appointments/book", [
                'date' => $date,
                'time' => $time,
                'provider_id' => $provider->id,
                'booked_for' => 'other',
                'recipient_name' => '  Rohan  ',
                'recipient_gender' => 'male',
                'recipient_phone' => '98765 43210',
            ])->assertStatus(201);

        $appointment = Appointment::find($response->json('appointment.id'));
        $this->assertSame($this->customer->id, $appointment->customer_id);
        $this->assertSame('other', $appointment->booked_for);
        $this->assertSame('Rohan', $appointment->recipient_name);
        $this->assertSame('male', $appointment->recipient_gender);
        $this->assertSame('9876543210', $appointment->recipient_phone);

        // The salon's check-in screen names both people.
        $present = app(\App\Services\AppointmentCheckInService::class)->present($appointment->load('customer'));
        $this->assertSame('Rohan', $present['recipient_name']);
        $this->assertSame($this->customer->name, $present['customer_name']);
    }

    public function test_booking_for_someone_else_needs_their_name(): void
    {
        [$salon, $provider, $date, $time] = $this->readyToBook($this->mensCut);

        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$salon->id}/appointments/book", [
                'date' => $date,
                'time' => $time,
                'provider_id' => $provider->id,
                'booked_for' => 'other',
            ])->assertStatus(422)->assertJsonValidationErrors('recipient_name', 'errors');
    }

    public function test_a_gender_mismatch_never_blocks_the_booking(): void
    {
        // She books a men's cut for herself. The app warns; the server does not refuse.
        [$salon, $provider, $date, $time] = $this->readyToBook($this->mensCut);

        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$salon->id}/appointments/book", [
                'date' => $date,
                'time' => $time,
                'provider_id' => $provider->id,
                'booked_for' => 'self',
                'recipient_name' => 'ignored',
            ])->assertStatus(201);

        $appointment = Appointment::find($response->json('appointment.id'));
        $this->assertSame('self', $appointment->booked_for);
        $this->assertNull($appointment->recipient_name);
    }
}
