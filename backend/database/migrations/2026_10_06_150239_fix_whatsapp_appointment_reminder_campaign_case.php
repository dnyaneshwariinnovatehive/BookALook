<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        DB::table('whatsapp_automations')
            ->where('key', 'whatsapp_appointment_reminder')
            ->update(['aisensy_campaign_name' => 'BAL_apt_reminder']);
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        //
    }
};
