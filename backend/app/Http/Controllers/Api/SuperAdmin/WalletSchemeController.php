<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\WalletScheme;
use App\Models\WalletSchemeTier;

class WalletSchemeController extends Controller
{
    public function index()
    {
        $schemes = WalletScheme::with('tiers')->get();
        return response()->json([
            'success' => true,
            'schemes' => $schemes
        ]);
    }

    public function store(Request $request)
    {
        $request->validate([
            'name' => 'required|string',
            'coin_value' => 'required|numeric',
            'tiers' => 'array'
        ]);

        $scheme = WalletScheme::create($request->only('name', 'coin_value', 'is_active', 'start_date', 'end_date'));

        if ($request->has('tiers')) {
            foreach ($request->tiers as $tier) {
                $scheme->tiers()->create($tier);
            }
        }

        return response()->json([
            'success' => true,
            'scheme' => $scheme->load('tiers')
        ]);
    }

    public function update(Request $request, $id)
    {
        $scheme = WalletScheme::findOrFail($id);
        $scheme->update($request->only('name', 'coin_value', 'is_active', 'start_date', 'end_date'));

        if ($request->has('tiers')) {
            $scheme->tiers()->delete();
            foreach ($request->tiers as $tier) {
                $scheme->tiers()->create($tier);
            }
        }

        return response()->json([
            'success' => true,
            'scheme' => $scheme->load('tiers')
        ]);
    }

    public function destroy($id)
    {
        $scheme = WalletScheme::findOrFail($id);
        $scheme->tiers()->delete();
        $scheme->delete();

        return response()->json([
            'success' => true
        ]);
    }
}
