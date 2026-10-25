<?php

namespace Tests\Feature;

use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The add-ons an owner links to a service are kept, shown back to them, and
 * are what the customer is offered first.
 */
class ServiceUpsellsTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;
    private User $owner;
    private Salon $salon;
    private ServiceCategory $category;
    private ServiceProvider $staff;
    private Service $haircut;
    private Service $hairSpa;
    private Service $beard;
    private Service $otherSalonService;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->owner = $this->user('admin', 'own');
        $this->salon = $this->salon($this->owner, 'a');
        $this->category = ServiceCategory::create(['name' => "Hair {$this->unique}", 'is_active' => true]);

        $this->staff = ServiceProvider::create([
            'user_id' => $this->user('service_provider', 'st')->id,
            'salon_id' => $this->salon->id,
            'is_active' => true,
        ]);

        $this->haircut = $this->service($this->salon, 'Haircut', 300);
        $this->hairSpa = $this->service($this->salon, 'Hair Spa', 800);
        $this->beard = $this->service($this->salon, 'Beard Trim', 150);
        $this->staff->services()->attach([$this->haircut->id, $this->hairSpa->id, $this->beard->id]);

        $other = $this->salon($this->user('admin', 'oth'), 'b');
        $this->otherSalonService = $this->service($other, 'Elsewhere', 100);
    }

    private function user(string $role, string $tag): User
    {
        return User::create([
            'id' => (string) Str::uuid(),
            'role' => $role,
            'name' => "{$tag} {$this->unique}",
            'phone' => '6'.substr((string) crc32($this->unique.$tag), 0, 9),
            'password_hash' => bcrypt('password'),
            'is_active' => true,
        ]);
    }

    private function salon(User $owner, string $tag): Salon
    {
        $salon = Salon::create([
            'admin_id' => $owner->id,
            'name' => "Upsell {$tag} {$this->unique}",
            'slug' => "upsell-{$tag}-{$this->unique}",
            'address' => '1 Upsell Road',
            'status' => 'active',
            'submitted_by' => $owner->id,
        ]);
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Growth Plan', 'price' => 999, 'duration_days' => 30, 'is_active' => true,
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

        return $salon;
    }

    private function service(Salon $salon, string $name, float $price): Service
    {
        $template = ServiceTemplate::create([
            'category_id' => ($this->category ??= ServiceCategory::create(['name' => "Hair {$this->unique}", 'is_active' => true]))->id,
            'name' => "{$name} {$this->unique}",
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        return Service::create([
            'salon_id' => $salon->id, 'template_id' => $template->id, 'price' => $price, 'is_active' => true,
        ]);
    }

    public function test_links_are_saved_when_a_service_is_added(): void
    {
        Sanctum::actingAs($this->owner);
        $template = ServiceTemplate::create([
            'category_id' => $this->category->id,
            'name' => "Colour {$this->unique}",
            'estimated_duration_minutes' => 60,
            'is_active' => true,
        ]);

        $response = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $template->id,
            'price' => 1500,
            // Another salon's service and a junk id are dropped, not refused.
            'linked_service_ids' => [$this->hairSpa->id, $this->otherSalonService->id, 'nope', $this->haircut->id],
        ])->assertStatus(200);

        $this->assertSame([$this->hairSpa->id, $this->haircut->id], $response->json('service.linked_service_ids'));
    }

    public function test_editing_replaces_reorders_and_clears_links(): void
    {
        Sanctum::actingAs($this->owner);
        $url = "/api/partner/salons/{$this->salon->id}/services/{$this->haircut->id}";

        $this->putJson($url, ['linked_service_ids' => [$this->beard->id, $this->hairSpa->id, $this->haircut->id]])
            ->assertStatus(200)
            ->assertJsonPath('service.linked_service_ids', [$this->beard->id, $this->hairSpa->id]);

        // Leaving the field out keeps them.
        $this->putJson($url, ['price' => 350])->assertStatus(200);
        $this->assertSame(2, $this->haircut->upsells()->count());

        $this->putJson($url, ['linked_service_ids' => []])
            ->assertStatus(200)
            ->assertJsonPath('service.linked_service_ids', []);
    }

    public function test_salon_services_list_shows_links_back_to_the_owner(): void
    {
        $this->haircut->upsells()->sync([$this->hairSpa->id => ['display_order' => 0]]);
        Sanctum::actingAs($this->owner);

        $services = collect($this->getJson("/api/partner/salons/{$this->salon->id}/services")
            ->assertStatus(200)
            ->json('grouped_services'))
            ->flatMap(fn ($g) => $g['services'])
            ->keyBy('id');

        $this->assertSame([$this->hairSpa->id], $services[$this->haircut->id]['linked_service_ids']);
        $this->assertSame([], $services[$this->beard->id]['linked_service_ids']);
    }

    public function test_cart_offers_the_owners_picks_first(): void
    {
        $this->haircut->upsells()->sync([$this->hairSpa->id => ['display_order' => 0]]);
        $customer = $this->user('customer', 'cu');

        $cart = Cart::create(['customer_id' => $customer->id, 'salon_id' => $this->salon->id, 'status' => 'active']);
        CartItem::create(['cart_id' => $cart->id, 'service_id' => $this->haircut->id, 'quantity' => 1]);

        $suggestions = $this->actingAs($customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/cart")
            ->assertStatus(200)
            ->json('cart.suggestions');

        $this->assertSame($this->hairSpa->id, $suggestions[0]['id']);
        $this->assertSame('salon_pick', $suggestions[0]['reason']);
        $this->assertSame($this->haircut->template->name, $suggestions[0]['paired_with']);
        $this->assertSame(30, $suggestions[0]['duration_minutes']);
        $this->assertCount(1, collect($suggestions)->where('id', $this->hairSpa->id));
    }

    public function test_a_pick_nobody_can_perform_is_not_offered(): void
    {
        $untrained = $this->service($this->salon, 'Keratin', 3000);
        $this->haircut->upsells()->sync([$untrained->id => ['display_order' => 0]]);
        $customer = $this->user('customer', 'cu');

        $cart = Cart::create(['customer_id' => $customer->id, 'salon_id' => $this->salon->id, 'status' => 'active']);
        CartItem::create(['cart_id' => $cart->id, 'service_id' => $this->haircut->id, 'quantity' => 1]);

        $suggestions = collect($this->actingAs($customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/cart")
            ->json('cart.suggestions'));

        $this->assertFalse($suggestions->contains('reason', 'salon_pick'));
    }

    public function test_salon_page_lists_each_services_picks(): void
    {
        $this->haircut->upsells()->sync([$this->hairSpa->id => ['display_order' => 0]]);

        $services = collect($this->getJson("/api/customer/salons/{$this->salon->id}")
            ->assertStatus(200)
            ->json('salon.services'))->keyBy('id');

        $this->assertSame([$this->hairSpa->id], $services[$this->haircut->id]['upsell_ids']);
        $this->assertSame([], $services[$this->hairSpa->id]['upsell_ids']);
    }
}
