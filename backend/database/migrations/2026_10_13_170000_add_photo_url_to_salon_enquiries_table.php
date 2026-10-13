<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salon_enquiries', function (Blueprint $table) {
            if (!Schema::hasColumn('salon_enquiries', 'photo_url')) {
                $table->string('photo_url', 500)->nullable()->after('message');
            }
        });
    }

    public function down(): void
    {
        Schema::table('salon_enquiries', function (Blueprint $table) {
            if (Schema::hasColumn('salon_enquiries', 'photo_url')) {
                $table->dropColumn('photo_url');
            }
        });
    }
};
