<?php

namespace Tests\Feature;

use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\SalonSubscription;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

class CartDuplicatePreventionTest extends TestCase
{
    use DatabaseTransactions;
    use \Tests\Feature\Concerns\ActivatesSalons;

    private User $customer;
    private Salon $salon;
    private Service $serviceA;
    private Service $serviceB;
    private Combo $combo;

    protected function setUp(): void
    {
        parent::setUp();

        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $this->customer = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Customer {$unique}",
            'phone' => '98' . substr((string) crc32($unique), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $admin = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Admin {$unique}",
            'phone' => '97' . substr((string) crc32($unique), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'admin',
            'is_active' => true,
        ]);

        $this->salon = Salon::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'admin_id' => $admin->id,
            'name' => "Salon {$unique}",
            'slug' => "salon-{$unique}",
            'address' => '123 Test Street',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);
        $this->activateSalon($this->salon);

        $category = ServiceCategory::firstOrCreate(
            ['name' => 'Hair Care'],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'is_active' => true]
        );

        $templateA = ServiceTemplate::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Haircut {$unique}",
            'category_id' => $category->id,
            'is_active' => true,
        ]);

        $templateB = ServiceTemplate::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Shampoo {$unique}",
            'category_id' => $category->id,
            'is_active' => true,
        ]);

        $this->serviceA = Service::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $templateA->id,
            'price' => 500.0,
            'advance_percentage' => 20,
            'is_active' => true,
            'display_order' => 1,
        ]);

        $this->serviceB = Service::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $templateB->id,
            'price' => 300.0,
            'advance_percentage' => 20,
            'is_active' => true,
            'display_order' => 2,
        ]);

        $this->combo = Combo::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'salon_id' => $this->salon->id,
            'name' => "Combo Pack {$unique}",
            'advance_percentage' => 25,
            'is_active' => true,
        ]);

        $this->combo->services()->attach($this->serviceA->id, ['combo_special_price' => 400.0]);
        $this->combo->services()->attach($this->serviceB->id, ['combo_special_price' => 250.0]);
    }

    public function test_first_add_creates_one_cart_line_with_quantity_one(): void
    {
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ]);

        $response->assertStatus(200);
        $cart = $response->json('cart');

        $this->assertCount(1, $cart['items']);
        $this->assertSame($this->serviceA->id, $cart['items'][0]['service_id']);
        $this->assertEquals(1, $cart['items'][0]['quantity']);

        $dbItem = CartItem::where('service_id', $this->serviceA->id)->first();
        $this->assertNotNull($dbItem);
        $this->assertEquals(1, $dbItem->quantity);
    }

    public function test_repeated_add_of_same_service_is_idempotent_and_does_not_increment_quantity(): void
    {
        // First add
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ])
            ->assertStatus(200);

        // Second add of the same service
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ]);

        $response->assertStatus(200);
        $cart = $response->json('cart');

        // Must still have exactly 1 line with quantity = 1
        $this->assertCount(1, $cart['items']);
        $this->assertSame($this->serviceA->id, $cart['items'][0]['service_id']);
        $this->assertEquals(1, $cart['items'][0]['quantity']);

        // Database must have only 1 row for this service
        $itemsCount = CartItem::where('service_id', $this->serviceA->id)->count();
        $this->assertEquals(1, $itemsCount);
        $this->assertEquals(1, CartItem::where('service_id', $this->serviceA->id)->first()->quantity);
    }

    public function test_adding_service_with_quantity_greater_than_one_returns_422(): void
    {
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
                'quantity' => 2,
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['quantity']);

        // Verify nothing was added
        $this->assertEquals(0, CartItem::where('service_id', $this->serviceA->id)->count());
    }

    public function test_updating_service_item_quantity_beyond_one_returns_422(): void
    {
        // Add service
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ])
            ->assertStatus(200);

        $item = CartItem::where('service_id', $this->serviceA->id)->first();

        // Attempt PATCH with quantity 2
        $response = $this->actingAs($this->customer, 'sanctum')
            ->patchJson("/api/customer/cart/items/{$item->id}", [
                'quantity' => 2,
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['quantity']);

        // Quantity in DB must remain 1
        $this->assertEquals(1, $item->fresh()->quantity);
    }

    public function test_updating_service_item_quantity_to_zero_removes_the_item(): void
    {
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ])
            ->assertStatus(200);

        $item = CartItem::where('service_id', $this->serviceA->id)->first();

        $response = $this->actingAs($this->customer, 'sanctum')
            ->patchJson("/api/customer/cart/items/{$item->id}", [
                'quantity' => 0,
            ]);

        $response->assertStatus(200);
        $this->assertNull(CartItem::find($item->id));
        $this->assertEmpty($response->json('cart.items'));
    }

    public function test_different_services_can_coexist_each_with_quantity_one(): void
    {
        // Add Service A
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ])
            ->assertStatus(200);

        // Add Service B
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceB->id,
            ]);

        $response->assertStatus(200);
        $cart = $response->json('cart');

        $this->assertCount(2, $cart['items']);
        $serviceIds = collect($cart['items'])->pluck('service_id')->all();
        $this->assertContains($this->serviceA->id, $serviceIds);
        $this->assertContains($this->serviceB->id, $serviceIds);

        foreach ($cart['items'] as $item) {
            $this->assertEquals(1, $item['quantity']);
        }
    }

    public function test_direct_combo_items_remain_unaffected(): void
    {
        // Add direct combo package
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'combo_id' => $this->combo->id,
                'quantity' => 2,
            ]);

        $response->assertStatus(200);
        $cart = $response->json('cart');

        $this->assertCount(1, $cart['items']);
        $this->assertSame($this->combo->id, $cart['items'][0]['combo_id']);
        $this->assertNull($cart['items'][0]['service_id']);
        $this->assertEquals(2, $cart['items'][0]['quantity']);

        // Update direct combo quantity
        $item = CartItem::where('combo_id', $this->combo->id)->first();
        $updateRes = $this->actingAs($this->customer, 'sanctum')
            ->patchJson("/api/customer/cart/items/{$item->id}", [
                'quantity' => 3,
            ]);

        $updateRes->assertStatus(200);
        $this->assertEquals(3, $item->fresh()->quantity);
    }

    public function test_database_unique_index_prevents_duplicate_service_lines_in_same_cart(): void
    {
        $cart = Cart::create([
            'customer_id' => $this->customer->id,
            'salon_id' => $this->salon->id,
            'status' => 'active',
        ]);

        CartItem::create([
            'cart_id' => $cart->id,
            'service_id' => $this->serviceA->id,
            'quantity' => 1,
        ]);

        $this->expectException(\Illuminate\Database\QueryException::class);

        // Attempting to insert a duplicate service row directly into DB must throw QueryException
        CartItem::create([
            'cart_id' => $cart->id,
            'service_id' => $this->serviceA->id,
            'quantity' => 1,
        ]);
    }
}
