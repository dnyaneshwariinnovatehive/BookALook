<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Service;
use App\Models\Combo;
use App\Services\AvailabilityService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CartController extends Controller
{
    public function __construct(private AvailabilityService $availability)
    {
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

        return response()->json(['cart' => $this->withSummary($cart)]);
    }

    /**
     * Serialise a cart with the money and duration the booking engine will
     * actually charge, so the app never has to re-derive prices itself. Combo
     * lines in particular are priced from their special prices, not from the
     * member services' list prices.
     */
    private function withSummary(Cart $cart): array
    {
        $requirements = $this->availability->summariseCart($cart);

        $payload = $cart->toArray();
        $payload['summary'] = [
            'item_count' => (int) $cart->items->sum(fn ($item) => max(1, (int) $item->quantity)),
            'total_amount' => $requirements['total'],
            'advance_amount' => $requirements['advance'],
            'total_duration_minutes' => $requirements['duration'],
        ];

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

        // Check if item already exists
        $existingItem = CartItem::where('cart_id', $cart->id)
            ->where('service_id', $request->service_id)
            ->where('combo_id', $request->combo_id)
            ->first();

        if ($existingItem) {
            $existingItem->quantity += $request->get('quantity', 1);
            $existingItem->preferred_provider_id = $request->preferred_provider_id;
            $existingItem->is_any_available = $request->get('is_any_available', false);
            $existingItem->save();
        } else {
            CartItem::create([
                'cart_id' => $cart->id,
                'service_id' => $request->service_id,
                'combo_id' => $request->combo_id,
                'preferred_provider_id' => $request->preferred_provider_id,
                'is_any_available' => $request->get('is_any_available', false),
                'quantity' => $request->get('quantity', 1)
            ]);
        }

        return response()->json(['message' => 'Item added to cart', 'cart' => $cart->load('items')]);
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
