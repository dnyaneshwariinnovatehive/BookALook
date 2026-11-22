<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Puts every user's account_type back in step with their role.
 *
 * In production the API kept serving pre-2026-11-22 code after that day's
 * deploy (PHP OPcache with validate_timestamps off, and PHP-FPM was not
 * reloaded), so a salon owner registered that evening was saved without the
 * User model's account_type hook and got the column default, 'customer'. The
 * Customer app then found the owner's account under that number and refused
 * the login. Safe to run any number of times: it only fixes mismatches.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('users')
            ->where('role', '!=', 'customer')
            ->where('account_type', '!=', 'partner')
            ->update(['account_type' => 'partner']);

        DB::table('users')
            ->where('role', 'customer')
            ->where('account_type', '!=', 'customer')
            ->update(['account_type' => 'customer']);
    }

    public function down(): void
    {
        // Nothing to undo: the corrected values are the only valid ones.
    }
};
