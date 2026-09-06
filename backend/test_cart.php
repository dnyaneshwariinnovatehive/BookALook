<?php
use Illuminate\Support\Facades\Schema;

echo "Carts table exists: " . (Schema::hasTable('carts') ? 'Yes' : 'No') . "\n";
echo "Cart_items table exists: " . (Schema::hasTable('cart_items') ? 'Yes' : 'No') . "\n";

echo "Cart Model exists: " . (class_exists('App\Models\Cart') ? 'Yes' : 'No') . "\n";
echo "CartItem Model exists: " . (class_exists('App\Models\CartItem') ? 'Yes' : 'No') . "\n";
