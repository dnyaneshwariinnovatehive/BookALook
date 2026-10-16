<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('first_time_offers', function (Blueprint $table) {
            $table->foreignUuid('salon_id')->nullable()->after('id')->constrained('salons')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('first_time_offers', function (Blueprint $table) {
            $table->dropForeign(['salon_id']);
            $table->dropColumn('salon_id');
        });
    }
};
