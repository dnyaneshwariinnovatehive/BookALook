<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Salon;
use App\Services\AuditLogger;
use App\Services\BankDetailsService;
use Illuminate\Http\Request;

/**
 * A salon's bank details, from the admin panel.
 *
 * SuperAdmin is the one paying settlements, so it may see the full account
 * number — but only on request (?reveal=1), and every reveal is written to the
 * audit log. Every change is audited too, without the number itself.
 */
class SalonBankDetailsController extends Controller
{
    public function __construct(private BankDetailsService $bank)
    {
    }

    public function show(Request $request, string $id)
    {
        $salon = Salon::findOrFail($id);
        $reveal = $request->boolean('reveal') && filled($salon->bank_account_number);

        if ($reveal) {
            AuditLogger::record(
                action: AuditLog::SALON_BANK_DETAILS_REVEALED,
                entity: $salon,
                label: $salon->name,
            );
        }

        return response()->json([
            'success' => true,
            'bank_details' => $this->bank->present($salon, $reveal),
        ]);
    }

    public function update(Request $request, string $id)
    {
        $salon = Salon::findOrFail($id);
        $before = $this->bank->present($salon);

        $clean = $this->bank->validate($request->only(BankDetailsService::FIELDS), $salon);
        $changed = $this->bank->apply($salon, $clean, $request->user());

        $salon->refresh();
        $after = $this->bank->present($salon);

        if ($changed) {
            // The masked view only: the audit log must not become a second
            // place full account numbers live.
            $strip = fn (array $d) => array_intersect_key($d, array_flip([
                'account_holder_name', 'bank_name', 'ifsc', 'upi_id', 'account_number_last4',
            ]));

            AuditLogger::record(
                action: AuditLog::SALON_BANK_DETAILS_UPDATED,
                entity: $salon,
                label: $salon->name,
                before: $strip($before),
                after: $strip($after),
            );
        }

        return response()->json([
            'success' => true,
            'message' => 'Bank details saved.',
            'bank_details' => $after,
        ]);
    }
}
