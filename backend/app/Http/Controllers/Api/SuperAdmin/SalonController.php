<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SalonController extends Controller
{
    public function index(Request $request)
    {
        $query = \App\Models\Salon::with(['admin', 'city']);

        if ($request->has('search') && $request->search != '') {
            $search = $request->input('search');
            $query->where(function($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhereHas('city', function($qc) use ($search) {
                      $qc->where('name', 'like', "%{$search}%");
                  });
            });
        }

        if ($request->has('status') && $request->status != '') {
            $query->where('status', $request->input('status'));
        }

        $salons = $query->orderBy('created_at', 'desc')->paginate(20);

        return response()->json([
            'success' => true,
            'data' => $salons->items(),
            'meta' => [
                'current_page' => $salons->currentPage(),
                'last_page' => $salons->lastPage(),
                'total' => $salons->total(),
            ]
        ]);
    }

    public function show($id)
    {
        $salon = \App\Models\Salon::with([
            'admin', 
            'city',
            'services.template.category',
            'providers.user',
            'combos.services'
        ])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $salon
        ]);
    }
}
