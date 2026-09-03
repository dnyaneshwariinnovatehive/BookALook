<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Salon;
use Illuminate\Support\Str;

class SalonApprovalController extends Controller
{
    /**
     * Display a listing of pending salons.
     */
    public function index()
    {
        $salons = Salon::with(['admin', 'city'])
            ->where('status', 'pending_approval')
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $salons
        ]);
    }

    /**
     * Display the specified salon details.
     */
    public function show($id)
    {
        $salon = Salon::with(['admin', 'city'])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $salon
        ]);
    }

    /**
     * Approve the salon.
     */
    public function approve($id)
    {
        $salon = Salon::findOrFail($id);

        // Generate a dummy QR code URL for now (e.g. using qrserver API)
        $dummyQrCodeUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=salon_' . $salon->id;

        $salon->update([
            'status' => 'active',
            'qr_code_url' => $dummyQrCodeUrl,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Salon approved successfully. QR Code generated.',
            'data' => $salon
        ]);
    }

    /**
     * Reject the salon.
     */
    public function reject(Request $request, $id)
    {
        $request->validate([
            'rejection_reason' => 'required|string|max:500'
        ]);

        $salon = Salon::findOrFail($id);
        
        $salon->update([
            'status' => 'rejected',
            'rejection_reason' => $request->rejection_reason
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Salon rejected successfully.',
            'data' => $salon
        ]);
    }
}
