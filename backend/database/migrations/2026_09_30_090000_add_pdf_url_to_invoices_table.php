<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where an invoice's PDF lives once it has been rendered.
 *
 * Held on the invoice rather than regenerated per send because the URL is what a
 * WhatsApp message points at, and a message that is retried must point at the
 * same file. Re-rendering would mint a second copy in the media library on every
 * retry and leave the customer holding a receipt for an amount that has since
 * changed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('invoices', function (Blueprint $table) {
            $table->text('pdf_url')->nullable()->after('template');
        });
    }

    public function down(): void
    {
        Schema::table('invoices', function (Blueprint $table) {
            $table->dropColumn('pdf_url');
        });
    }
};