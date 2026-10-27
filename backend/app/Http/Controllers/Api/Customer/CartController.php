<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Service;
use App\Models\Combo;
use App\Services\AvailabilityService;
use App\Services\CartPricingService;
use App\Support\GenderFocus;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CartController extends Controller
{
    public function __construct(
        private AvailabilityService $availability,
        private CartPricingService $pricing,
    ) {
    }

    /**
     * Get the current user's cart for a specific salon.
     */
    public function getCart(Request $request, $salon_id)
    {
        $cart = Cart::with(['items.service.template', 'items.combo.services.template', 'items.preferredProvider.user'])
            ->where('customer_id', $request->user()->id)
            ->where('salon_id', $salon_id)
            ->where('status', 'active')
            ->first();

        if (!$cart) {
            return response()->json(['message' => 'Cart is empty', 'cart' => null]);
        }

        $this->purgeRetiredItems($cart);

        if ($cart->items()->count() === 0) {
            return response()->json(['message' => 'Cart is empty', 'cart' => null]);
        }

        $cart->load(['items.service.template', 'items.combo.services.template', 'items.preferredProvider.user']);

        return response()->json(['cart' => $this->withSummary($cart)]);
    }

    /**
     * Get the current user's global active cart across all salons.
     */
    public function getGlobalCart(Request $request)
    {
        $cart = Cart::with(['items.service.template', 'items.combo.services.template', 'items.preferredProvider.user', 'salon'])
            ->where('customer_id', $request->user()->id)
            ->where('status', 'active')
            ->first();

        if (!$cart) {
            return response()->json(['message' => 'Cart is empty', 'cart' => null]);
        }

        $this->purgeRetiredItems($cart);

        if ($cart->items()->count() === 0) {
            return response()->json(['message' => 'Cart is empty', 'cart' => null]);
        }

        $cart->load(['items.service.template', 'items.combo.services.template', 'items.preferredProvider.user', 'salon']);

        return response()->json(['cart' => $this->withSummary($cart)]);
    }

    /**
     * Remove any items whose service or template has been retired or deactivated.
     */
    private function purgeRetiredItems(Cart $cart): array
    {
        $removed = [];
        foreach ($cart->items as $item) {
            if ($item->service_id) {
                $service = $item->service;
                if (! $service || ! $service->is_active || $service->trashed() || ! $service->template || ! $service->template->is_active || $service->template->trashed()) {
                    $removed[] = $service?->template?->name ?? 'Service';
                    $item->delete();
                }
            } elseif ($item->combo_id) {
                $combo = $item->combo;
                if (! $combo || ! $combo->is_active) {
                    $removed[] = $combo?->name ?? 'Package';
                    $item->delete();
                }
            }
        }
        return $removed;
    }

    /**
     * Serialise a cart with the money and duration the booking engine will
     * actually charge, so the app never has to re-derive prices itself. Combo
     * lines in particular are priced from their special prices, not from the
     * member services' list prices.
     */
    private function withSummary(Cart $cart): array
    {
        $priced = $this->pricing->price($cart);

        $payload = $cart->toArray();

        // Who each line is for once the salon's focus applies, so checkout can
        // warn when someone books a Men Only service for a woman. A combo
        // mixing both is 'Mixed' and never warns.
        $salonFocus = \App\Models\Salon::whereKey($cart->salon_id)->value('gender_focus');
        $audienceOf = function (array $services) use ($salonFocus): string {
            $audiences = collect($services)
                ->map(fn ($s) => GenderFocus::effective($s['gender_focus'] ?? null, $salonFocus))
                ->reject(fn ($a) => $a === GenderFocus::UNISEX)
                ->unique()
                ->values();

            return match ($audiences->count()) {
                0 => GenderFocus::effective(null, $salonFocus),
                1 => $audiences->first(),
                default => 'Mixed',
            };
        };

        if (!empty($payload['items'])) {
            foreach ($payload['items'] as &$item) {
                $qty = max(1, (int) ($item['quantity'] ?? 1));
                $item['audience'] = !empty($item['combo'])
                    ? $audienceOf($item['combo']['services'] ?? [])
                    : $audienceOf(!empty($item['service']) ? [$item['service']] : []);
                if (!empty($item['combo'])) {
                    $itemPrice = (float) ($item['combo']['price'] ?? 0);
                    if ($itemPrice <= 0 && !empty($item['combo']['services'])) {
                        $itemPrice = (float) array_sum(array_map(function ($s) {
                            return (float) ($s['pivot']['combo_special_price'] ?? $s['price'] ?? 0);
                        }, $item['combo']['services']));
                        $item['combo']['price'] = round($itemPrice, 2);
                    }
                    $item['price'] = round($itemPrice, 2);
                    $item['line_total'] = round($itemPrice * $qty, 2);
                } elseif (!empty($item['service'])) {
                    $itemPrice = (float) ($item['service']['price'] ?? 0);
                    $lineTotal = round($itemPrice * $qty, 2);
                    $item['price'] = round($itemPrice, 2);
                    $item['line_total'] = $lineTotal;

                    $ftoLine = $priced['first_time_discount']['lines'][$item['service_id']] ?? null;
                    if ($ftoLine && ($ftoLine['line_discount'] ?? 0) > 0) {
                        $item['first_time_discount_amount'] = (float) $ftoLine['line_discount'];
                        $item['final_price'] = (float) $ftoLine['final_line_price'];
                    } else {
                        $item['first_time_discount_amount'] = 0.0;
                        $item['final_price'] = $lineTotal;
                    }
                }
            }
        }

        $payload['summary'] = [
            'item_count' => $priced['item_count'],
            'total_amount' => $priced['total'],
            // What the same services would cost bought separately, so a
            // discount can be shown as a saving rather than just a lower number.
            'list_total' => $priced['list_total'],
            'saving' => $priced['saving'],
            'advance_amount' => $priced['advance'],
            'total_duration_minutes' => $priced['duration'],
            'first_time_discount' => $priced['first_time_discount'] ?? null,
        ];

        // Packages the cart already qualifies for, applied automatically.
        $payload['applied_combos'] = array_map(fn ($combo) => [
            'combo_id' => $combo['combo_id'],
            'name' => $combo['name'],
            'applications' => $combo['applications'],
            'combo_total' => $combo['combo_total'],
            'list_total' => $combo['list_total'],
            'saving' => $combo['saving'],
            'service_names' => array_column($combo['services'], 'name'),
        ], $priced['applied_combos']);

        // Packages they are one or two services away from.
        $payload['combo_offers'] = $this->pricing->comboOffers($cart);

        // What this salon's customers usually add alongside.
        $payload['suggestions'] = $this->pricing->suggestions($cart);

        return $payload;
    }

    /**
     * Add an item to the cart.
     */
    public function addItem(Request $request, $salon_id)
    {
        $validator = Validator::make($request->all(), [
            'service_id' => 'nullable|exists:services,id',
            'combo_id' => 'nullable|exists:combos,id',
            'preferred_provider_id' => 'nullable|exists:service_providers,id',
            'is_any_available' => 'boolean',
            'quantity' => 'integer|min:1'
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if (!$request->service_id && !$request->combo_id) {
            return response()->json(['message' => 'Either service_id or combo_id is required.'], 400);
        }

        // A salon that cannot serve bookings right now (plan lapsed, commission
        // unsettled, suspended) should not fill a basket the customer can never
        // check out.
        if (! app(\App\Services\SalonAccessService::class)->isActive($salon_id)) {
            return response()->json([
                'message' => 'This salon is not taking bookings right now. Please choose another salon.',
                'salon_unavailable' => true,
            ], 409);
        }

        // One of each: a service or a combo is booked once per visit.
        if ($request->has('quantity') && (int) $request->quantity > 1) {
            $what = $request->filled('combo_id') ? 'A combo' : 'An individual service';

            return response()->json([
                'message' => "{$what} can only be added once.",
                'errors' => [
                    'quantity' => ['The quantity must always be 1.']
                ]
            ], 422);
        }

        // Enforce single active cart rule
        $activeCart = Cart::with('salon')->where('customer_id', $request->user()->id)
            ->where('status', 'active')
            ->first();
            
        if ($activeCart && $activeCart->salon_id != $salon_id) {
            return response()->json([
                'message' => 'Your cart contains items from another salon.',
                'different_salon' => true,
                'current_salon_name' => $activeCart->salon->name ?? 'another salon'
            ], 409);
        }

        $cart = Cart::firstOrCreate(
            ['customer_id' => $request->user()->id, 'salon_id' => $salon_id, 'status' => 'active']
        );

        if ($request->service_id) {
            // Validate that the service is active, not retired/trashed, and belongs to an active template
            $activeService = Service::where('salon_id', $salon_id)
                ->where('is_active', true)
                ->whereHas('template', function ($q) {
                    $q->where('is_active', true);
                })
                ->find($request->service_id);

            if (! $activeService) {
                return response()->json([
                    'message' => 'This service is no longer available.',
                ], 422);
            }
            // Check if this service is already included in an existing combo in the cart
            $existingComboWithService = CartItem::where('cart_id', $cart->id)
                ->whereNotNull('combo_id')
                ->whereHas('combo.services', function ($q) use ($request) {
                    $q->where('services.id', $request->service_id);
                })
                ->with('combo')
                ->first();

            if ($existingComboWithService) {
                $comboName = $existingComboWithService->combo?->name ?? 'a combo';
                $cart->load(['items.service.template', 'items.combo.services.template']);
                return response()->json([
                    'message' => "This service is already included in '{$comboName}' in your cart.",
                    'already_in_combo' => true,
                    'combo_name' => $comboName,
                    'cart' => $this->withSummary($cart),
                ], 200);
            }

            $existingItem = CartItem::where('cart_id', $cart->id)
                ->where('service_id', $request->service_id)
                ->first();

            if ($existingItem) {
                // Idempotent: retain single line with quantity = 1, never increment
                $existingItem->quantity = 1;
                if ($request->has('preferred_provider_id')) {
                    $existingItem->preferred_provider_id = $request->preferred_provider_id;
                }
                if ($request->has('is_any_available')) {
                    $existingItem->is_any_available = $request->boolean('is_any_available');
                }
                $existingItem->save();
            } else {
                try {
                    CartItem::create([
                        'cart_id' => $cart->id,
                        'service_id' => $request->service_id,
                        'combo_id' => null,
                        'preferred_provider_id' => $request->preferred_provider_id,
                        'is_any_available' => $request->boolean('is_any_available', false),
                        'quantity' => 1
                    ]);
                } catch (\Illuminate\Database\QueryException $e) {
                    // In case of concurrent add requests, recover idempotently
                    $existingItem = CartItem::where('cart_id', $cart->id)
                        ->where('service_id', $request->service_id)
                        ->first();

                    if ($existingItem) {
                        $existingItem->quantity = 1;
                        if ($request->has('preferred_provider_id')) {
                            $existingItem->preferred_provider_id = $request->preferred_provider_id;
                        }
                        if ($request->has('is_any_available')) {
                            $existingItem->is_any_available = $request->boolean('is_any_available');
                        }
                        $existingItem->save();
                    } else {
                        throw $e;
                    }
                }
            }
        } else {
            // Direct combo packages
            $combo = Combo::with('services.template')->find($request->combo_id);
            if (!$combo) {
                return response()->json(['message' => 'Combo not found.'], 404);
            }

            // Check if cart already has individual services that are part of this combo
            $comboServiceIds = $combo->services->pluck('id')->all();

            $overlappingItems = CartItem::with('service.template')
                ->where('cart_id', $cart->id)
                ->whereIn('service_id', $comboServiceIds)
                ->get();

            $replacedServices = [];
            $totalListPriceOfReplaced = 0.0;
            if ($overlappingItems->isNotEmpty()) {
                foreach ($overlappingItems as $item) {
                    $serviceName = $item->service?->template?->name ?? 'Service';
                    $servicePrice = (float) ($item->service?->price ?? 0.0);
                    $totalListPriceOfReplaced += $servicePrice * max(1, (int) $item->quantity);
                    $replacedServices[] = [
                        'id' => $item->service_id,
                        'name' => $serviceName,
                        'price' => $servicePrice,
                    ];
                    $item->delete(); // Automatically delete the loose service line
                }
            }

            // Calculate savings:
            $comboListTotal = (float) $combo->original_price;
            $comboPrice = (float) $combo->price;
            $comboSaving = max(0.0, round($comboListTotal - $comboPrice, 2));
            $savedAmount = $comboSaving > 0 ? $comboSaving : $totalListPriceOfReplaced;

            $existingItem = CartItem::where('cart_id', $cart->id)
                ->where('combo_id', $request->combo_id)
                ->whereNull('service_id')
                ->first();

            if ($existingItem) {
                // Already in the basket: adding again changes nothing but the
                // provider choice — a combo is never more than one.
                $existingItem->quantity = 1;
                $existingItem->preferred_provider_id = $request->preferred_provider_id;
                $existingItem->is_any_available = $request->boolean('is_any_available', false);
                $existingItem->save();
            } else {
                CartItem::create([
                    'cart_id' => $cart->id,
                    'service_id' => null,
                    'combo_id' => $request->combo_id,
                    'preferred_provider_id' => $request->preferred_provider_id,
                    'is_any_available' => $request->boolean('is_any_available', false),
                    'quantity' => 1
                ]);
            }

            $message = 'Item added to cart';
            if (!empty($replacedServices)) {
                $serviceNames = implode(', ', array_unique(array_column($replacedServices, 'name')));
                $message = $savedAmount > 0
                    ? "You saved ₹" . number_format($savedAmount, 0) . "! Replaced {$serviceNames} with {$combo->name}."
                    : "Replaced {$serviceNames} with {$combo->name}.";
            }
        }

        // The enriched cart comes straight back so the app can show what this
        // unlocked — a completed package, or what to add next — at the moment
        // the customer is still deciding.
        $cart->load(['items.service.template', 'items.combo.services.template']);

        return response()->json([
            'message' => $message ?? 'Item added to cart',
            'replaced_services' => $replacedServices ?? [],
            'saved_amount' => $savedAmount ?? 0,
            'combo_name' => isset($combo) ? $combo->name : null,
            'cart' => $this->withSummary($cart),
        ]);
    }

    /**
     * Update quantity of an item in the cart.
     */
    public function updateItemQuantity(Request $request, $cart_item_id)
    {
        $validator = Validator::make($request->all(), [
            'quantity' => 'required|integer|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $item = CartItem::whereHas('cart', function ($q) use ($request) {
            $q->where('customer_id', $request->user()->id);
        })->find($cart_item_id);

        if (!$item) {
            return response()->json(['message' => 'Cart item not found.'], 404);
        }

        // Services and combos alike are one each.
        if ((int) $request->quantity > 1) {
            return response()->json([
                'message' => $item->combo_id !== null
                    ? 'A combo can only be added once.'
                    : 'Individual services cannot have a quantity greater than 1.',
                'errors' => [
                    'quantity' => ['The quantity must be 1.']
                ]
            ], 422);
        }

        $cart = $item->cart;

        if ($request->quantity <= 0) {
            $item->delete();
        } else {
            $item->quantity = $request->quantity;
            $item->save();
        }

        $cart->load(['items.service.template', 'items.combo.services.template', 'items.preferredProvider.user']);

        return response()->json([
            'message' => 'Cart updated.',
            'cart' => $this->withSummary($cart),
        ]);
    }

    /**
     * Remove an item from the cart.
     */
    public function removeItem(Request $request, $cart_item_id)
    {
        $item = CartItem::whereHas('cart', function ($q) use ($request) {
            $q->where('customer_id', $request->user()->id);
        })->find($cart_item_id);

        if (!$item) {
            return response()->json(['message' => 'Cart item not found.'], 404);
        }

        $item->delete();

        return response()->json(['message' => 'Item removed from cart.']);
    }

    /**
     * Clear the cart.
     */
    public function clearCart(Request $request, $salon_id)
    {
        $cart = Cart::where('customer_id', $request->user()->id)
            ->where('salon_id', $salon_id)
            ->where('status', 'active')
            ->first();

        if ($cart) {
            $cart->items()->delete();
            $cart->delete();
        }

        return response()->json(['message' => 'Cart cleared.']);
    }

    /**
     * Clear the user's global active cart.
     */
    public function clearGlobalCart(Request $request)
    {
        $cart = Cart::where('customer_id', $request->user()->id)
            ->where('status', 'active')
            ->first();

        if ($cart) {
            $cart->items()->delete();
            $cart->delete();
        }

        return response()->json(['message' => 'Global cart cleared.']);
    }
}
