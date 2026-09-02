<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SalonController extends Controller
{
    public function index(Request $request)
    {
        $query = DB::table('salons')->select('id', 'name', 'city');

        if ($request->has('search')) {
            $search = $request->input('search');
            $query->where('name', 'like', "%{$search}%");
        }

        $salons = $query->limit(50)->get();

        return response()->json($salons);
    }
}
