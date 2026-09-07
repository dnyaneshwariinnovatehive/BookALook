<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\SalonSubscription;
use App\Models\User;
use App\Services\CartPricingService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Combo-aware cart pricing and the suggestions built on top of it.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class CartComboPricingTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_cart_holding_a_whole_package_is_priced_as_that_package(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $combo = $this->givenCombo($salon, 'Grooming Pack', [
            [$services[0], 400.0],   // list 500
            [$services[1], 250.0],   // list 300
        ]);

        $cart = $this->givenCart($customer, $salon, [$services[0], $services[1]]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(650.0, $priced['total']);
        $this->assertEquals(800.0, $priced['list_total']);
        $this->assertEquals(150.0, $priced['saving']);

        $this->assertCount(1, $priced['applied_combos']);
        $this->assertSame($combo->id, $priced['applied_combos'][0]['combo_id']);
        $this->assertSame('Grooming Pack', $priced['applied_combos'][0]['name']);
        $this->assertEquals(150.0, $priced['applied_combos'][0]['saving']);

        // Nothing was left over to charge at list price.
        $this->assertSame([], $priced['loose_services']);
    }

    public function test_removing_one_service_quietly_reverts_to_list_prices(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $this->givenCombo($salon, 'Pair', [[$services[0], 400.0], [$services[1], 250.0]]);

        $cart = $this->givenCart($customer, $salon, [$services[0], $services[1]]);
        $this->assertEquals(650.0, app(CartPricingService::class)->price($cart)['total']);

        // The cart is only ever re-priced, never re-shaped, so breaking the set
        // needs no cleanup.
        CartItem::where('cart_id', $cart->id)->where('service_id', $services[1]->id)->delete();

        $priced = app(CartPricingService::class)->price($cart->fresh('items'));

        $this->assertEquals(500.0, $priced['total']);
        $this->assertEquals(0.0, $priced['saving']);
        $this->assertSame([], $priced['applied_combos']);
    }

    public function test_a_partly_filled_package_is_offered_with_what_it_would_save(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $combo = $this->givenCombo($salon, 'Trio', [
            [$services[0], 400.0],   // list 500 — in the cart
            [$services[1], 250.0],   // list 300 — missing
            [$services[2], 150.0],   // list 200 — missing
        ]);

        $cart = $this->givenCart($customer, $salon, [$services[0]]);

        $offers = app(CartPricingService::class)->comboOffers($cart);

        $this->assertCount(1, $offers);
        $offer = $offers[0];

        $this->assertSame($combo->id, $offer['combo_id']);
        $this->assertSame(['Service A'], $offer['services_in_cart']);
        $this->assertCount(2, $offer['missing_services']);
        // 1000 list vs 800 as a package.
        $this->assertEquals(200.0, $offer['saving']);
        // They already hold ₹500 of it, so ₹300 completes the package.
        $this->assertEquals(300.0, $offer['extra_to_pay']);
    }

    public function test_a_package_already_applied_is_not_offered_again(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $this->givenCombo($salon, 'Pair', [[$services[0], 400.0], [$services[1], 250.0]]);

        $cart = $this->givenCart($customer, $salon, [$services[0], $services[1]]);

        $this->assertSame([], app(CartPricingService::class)->comboOffers($cart));
    }

    public function test_the_biggest_saving_wins_when_packages_overlap(): void
    {
        [$salon, $customer, $services] = $this->fixture();

        // Both packages want Service A; only one can have it.
        $small = $this->givenCombo($salon, 'Small saving', [
            [$services[0], 480.0],   // saves 20
            [$services[1], 300.0],
        ]);
        $big = $this->givenCombo($salon, 'Big saving', [
            [$services[0], 300.0],   // saves 300
            [$services[2], 100.0],
        ]);

        $cart = $this->givenCart($customer, $salon, [$services[0], $services[1], $services[2]]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertCount(1, $priced['applied_combos']);
        $this->assertSame($big->id, $priced['applied_combos'][0]['combo_id']);
        // ₹400 for the package, plus Service B at its ₹300 list price since no
        // package could claim it.
        $this->assertEquals(700.0, $priced['total']);
        $this->assertCount(1, $priced['loose_services']);
        $this->assertSame($services[1]->id, $priced['loose_services'][0]['service_id']);
    }

    public function test_the_cart_endpoint_reports_the_saving_and_the_offers(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $this->givenCombo($salon, 'Grooming Pack', [[$services[0], 400.0], [$services[1], 250.0]]);
        $this->givenCart($customer, $salon, [$services[0], $services[1]]);

        $cart = $this->actingAs($customer, 'sanctum')
            ->getJson('/api/customer/cart')
            ->assertStatus(200)
            ->json('cart');

        $this->assertEquals(650.0, $cart['summary']['total_amount']);
        $this->assertEquals(800.0, $cart['summary']['list_total']);
        $this->assertEquals(150.0, $cart['summary']['saving']);

        $this->assertCount(1, $cart['applied_combos']);
        $this->assertSame('Grooming Pack', $cart['applied_combos'][0]['name']);
        $this->assertContains('Service A', $cart['applied_combos'][0]['service_names']);

        $this->assertArrayHasKey('combo_offers', $cart);
        $this->assertArrayHasKey('suggestions', $cart);
    }

    public function test_adding_an_item_returns_the_offer_it_unlocked(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $this->givenCombo($salon, 'Trio', [
            [$services[0], 400.0],
            [$services[1], 250.0],
            [$services[2], 150.0],
        ]);

        // The response the customer sees the moment they add the first service.
        $cart = $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/salons/{$salon->id}/cart/items", [
                'service_id' => $services[0]->id,
            ])
            ->assertStatus(200)
            ->json('cart');

        $this->assertCount(1, $cart['combo_offers']);
        $this->assertSame('Trio', $cart['combo_offers'][0]['name']);
        $this->assertEquals(200.0, $cart['combo_offers'][0]['saving']);
    }

    public function test_what_is_shown_is_what_is_charged(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $combo = $this->givenCombo($salon, 'Grooming Pack', [
            [$services[0], 400.0],
            [$services[1], 250.0],
        ]);

        $cart = $this->givenCart($customer, $salon, [$services[0], $services[1]]);

        // The availability engine drives checkout totals and the booking, so it
        // has to agree with the cart screen down to the rupee.
        $summary = app(\App\Services\AvailabilityService::class)->summariseCart($cart);
        $this->assertEquals(650.0, $summary['total']);

        $shown = $this->actingAs($customer, 'sanctum')
            ->getJson('/api/customer/cart')->json('cart.summary.total_amount');
        $this->assertEquals($summary['total'], $shown);
    }

    public function test_booking_records_the_package_the_customer_assembled(): void
    {
        [$salon, $customer, $services] = $this->fixture();
        $combo = $this->givenCombo($salon, 'Grooming Pack', [
            [$services[0], 400.0],
            [$services[1], 250.0],
        ]);

        $cart = $this->givenCart($customer, $salon, [$services[0], $services[1]]);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $this->anyProviderId($salon),
            'booking_source' => 'online',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '11:00:00',
            'status' => 'scheduled',
            'total_amount' => 650,
            'advance_amount' => 0,
            'balance_amount' => 650,
        ]);

        // Mirrors what book() does with the priced cart.
        $priced = app(CartPricingService::class)->price($cart);
        $servicesById = $cart->items->filter(fn ($i) => $i->service)
            ->mapWithKeys(fn ($i) => [$i->service_id => $i->service]);

        foreach ($priced['applied_combos'] as $match) {
            foreach ($match['services'] as $line) {
                \App\Models\AppointmentService::create([
                    'appointment_id' => $appointment->id,
                    'service_id' => $line['service_id'],
                    'combo_id' => $match['combo_id'],
                    'price_at_booking' => $line['combo_price'],
                    'original_service_price' => $servicesById[$line['service_id']]->price,
                    'duration_minutes_at_booking' => $line['duration_minutes'],
                    'line_status' => 'booked',
                ]);
            }
        }

        $lines = $appointment->services()->get();

        $this->assertCount(2, $lines);
        // Charged at package rates, and traceable back to the package.
        $this->assertEquals(650.0, (float) $lines->sum('price_at_booking'));
        $this->assertEquals(800.0, (float) $lines->sum('original_service_price'));
        $this->assertTrue($lines->every(fn ($l) => $l->combo_id === $combo->id));
    }

    public function test_suggestions_come_from_what_this_salon_actually_sells_together(): void
    {
        [$salon, $customer, $services] = $this->fixture();

        // Two completed appointments where A was booked with C.
        foreach ([1, 2] as $ignored) {
            $appointment = Appointment::create([
                'salon_id' => $salon->id,
                'customer_id' => $customer->id,
                'appointed_provider_id' => $this->anyProviderId($salon),
                'booking_source' => 'online',
                'appointment_date' => Carbon::today()->subDays(5)->toDateString(),
                'start_time' => '10:00:00',
                'end_time' => '11:00:00',
                'status' => 'completed',
                'total_amount' => 700,
                'advance_amount' => 0,
                'balance_amount' => 700,
            ]);

            foreach ([$services[0], $services[2]] as $service) {
                \App\Models\AppointmentService::create([
                    'appointment_id' => $appointment->id,
                    'service_id' => $service->id,
                    'price_at_booking' => $service->price,
                    'original_service_price' => $service->price,
                    'duration_minutes_at_booking' => 30,
                    'line_status' => 'completed',
                ]);
            }
        }

        $cart = $this->givenCart($customer, $salon, [$services[0]]);

        $suggestions = app(CartPricingService::class)->suggestions($cart);

        $top = collect($suggestions)->firstWhere('id', $services[2]->id);
        $this->assertNotNull($top, 'the service booked alongside was not suggested');
        $this->assertSame('bought_together', $top['reason']);
        $this->assertSame(100, $top['together_percent']);

        // What is already in the cart is never suggested back.
        $this->assertNull(collect($suggestions)->firstWhere('id', $services[0]->id));
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: array<int, Service>} */
    private function fixture(): array
    {
        $customer = User::where('role', 'customer')->first();
        $template = ServiceTemplate::first();

        if (! $customer || ! $template) {
            $this->markTestSkipped('needs a customer and a service template');
        }

        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Combo Admin {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Combo Salon {$unique}",
            'slug' => "combo-salon-{$unique}",
            'address' => 'Test address',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $plan = SubscriptionPlan::first();

        if ($plan) {
            SalonSubscription::create([
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => 'flat',
                'plan_price_snapshot' => $plan->price,
                'start_date' => Carbon::today()->subDay(),
                'end_date' => Carbon::today()->addDays(30),
                'status' => 'active',
            ]);
        }

        // Distinct templates so each service has its own name.
        $templates = ServiceTemplate::limit(3)->get();
        $names = ['Service A', 'Service B', 'Service C'];
        $prices = [500.0, 300.0, 200.0];
        $made = [];

        foreach ($prices as $index => $price) {
            $made[] = Service::create([
                'salon_id' => $salon->id,
                'template_id' => ($templates[$index] ?? $template)->id,
                'price' => $price,
                'advance_percentage' => 0,
                'is_active' => true,
                'display_order' => $index,
            ]);

            // The tests read names off the template, so make them predictable.
            ($templates[$index] ?? $template)->forceFill(['name' => $names[$index]])->save();
        }

        return [$salon, $customer, $made];
    }

    /** @param array<int, array{0: Service, 1: float}> $lines */
    private function givenCombo(Salon $salon, string $name, array $lines): Combo
    {
        $combo = Combo::create([
            'salon_id' => $salon->id,
            'name' => $name,
            'advance_percentage' => 0,
            'is_active' => true,
        ]);

        foreach ($lines as [$service, $comboPrice]) {
            $combo->services()->attach($service->id, ['combo_special_price' => $comboPrice]);
        }

        return $combo->fresh('services');
    }

    /** @param array<int, Service> $services */
    private function givenCart(User $customer, Salon $salon, array $services): Cart
    {
        Cart::where('customer_id', $customer->id)->where('status', 'active')->delete();

        $cart = Cart::create([
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => 'active',
        ]);

        foreach ($services as $service) {
            CartItem::create([
                'cart_id' => $cart->id,
                'service_id' => $service->id,
                'quantity' => 1,
            ]);
        }

        return $cart->fresh('items');
    }

    private function anyProviderId(Salon $salon): string
    {
        $provider = \App\Models\ServiceProvider::first();

        if (! $provider) {
            $this->markTestSkipped('needs at least one service provider');
        }

        return $provider->id;
    }
}
