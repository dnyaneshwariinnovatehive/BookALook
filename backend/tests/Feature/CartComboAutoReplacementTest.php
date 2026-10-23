<?php

namespace Tests\Feature;

use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

class CartComboAutoReplacementTest extends TestCase
{
    use DatabaseTransactions;

    private User $customer;
    private Salon $salon;
    private Service $serviceA;
    private Service $serviceB;
    private Service $serviceC;
    private Combo $comboAB;

    protected function setUp(): void
    {
        parent::setUp();

        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $this->customer = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Customer {$unique}",
            'phone' => '98' . substr((string) crc32($unique . 'c'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $admin = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Admin {$unique}",
            'phone' => '97' . substr((string) crc32($unique . 'a'), 0, 8),
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
            'name' => "Beard Trim {$unique}",
            'category_id' => $category->id,
            'is_active' => true,
        ]);

        $templateC = ServiceTemplate::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => "Head Massage {$unique}",
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

        $this->serviceC = Service::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $templateC->id,
            'price' => 400.0,
            'advance_percentage' => 20,
            'is_active' => true,
            'display_order' => 3,
        ]);

        // Combo AB: Haircut (500 list -> 400 combo) + Beard Trim (300 list -> 200 combo) = 600 total (saves 200)
        $this->comboAB = Combo::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'salon_id' => $this->salon->id,
            'name' => "Grooming Combo {$unique}",
            'is_active' => true,
        ]);

        $this->comboAB->services()->attach([
            $this->serviceA->id => ['combo_special_price' => 400.0],
            $this->serviceB->id => ['combo_special_price' => 200.0],
        ]);
    }

    public function test_adding_combo_automatically_removes_overlapping_loose_services_and_reports_savings(): void
    {
        // 1. Customer adds Service A to cart
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ])
            ->assertStatus(200);

        // 2. Also add Service C (which is NOT in the combo)
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceC->id,
            ])
            ->assertStatus(200);

        $cart = Cart::where('customer_id', $this->customer->id)->where('status', 'active')->first();
        $this->assertCount(2, $cart->items);

        // 3. Customer adds Combo AB
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'combo_id' => $this->comboAB->id,
            ]);

        $response->assertStatus(200);
        $data = $response->json();

        // Verify message mentions savings and replacement
        $this->assertStringContainsString('You saved ₹200!', $data['message']);
        $this->assertCount(1, $data['replaced_services']);
        $this->assertSame($this->serviceA->id, $data['replaced_services'][0]['id']);
        $this->assertEquals(200.0, $data['saved_amount']);

        // Verify cart items in DB: Service A was DELETED, Combo AB is present, Service C remains
        $updatedCartItems = CartItem::where('cart_id', $cart->id)->get();
        $this->assertCount(2, $updatedCartItems); // 1 combo + 1 loose service C

        $looseServiceIds = $updatedCartItems->whereNotNull('service_id')->pluck('service_id')->all();
        $this->assertNotContains($this->serviceA->id, $looseServiceIds);
        $this->assertContains($this->serviceC->id, $looseServiceIds);

        $comboIds = $updatedCartItems->whereNotNull('combo_id')->pluck('combo_id')->all();
        $this->assertContains($this->comboAB->id, $comboIds);
    }

    public function test_adding_service_already_in_cart_combo_is_prevented_with_informative_message(): void
    {
        // 1. Add Combo AB to cart first
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'combo_id' => $this->comboAB->id,
            ])
            ->assertStatus(200);

        // 2. Customer tries to add Service A (which is part of Combo AB)
        $response = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $this->serviceA->id,
            ]);

        $response->assertStatus(200);
        $this->assertTrue($response->json('already_in_combo'));
        $this->assertStringContainsString('already included', $response->json('message'));

        // Cart should still only contain the combo, no duplicate service A
        $cart = Cart::where('customer_id', $this->customer->id)->where('status', 'active')->first();
        $this->assertCount(1, $cart->items);
        $this->assertNull($cart->items[0]->service_id);
        $this->assertSame($this->comboAB->id, $cart->items[0]->combo_id);
    }
}
