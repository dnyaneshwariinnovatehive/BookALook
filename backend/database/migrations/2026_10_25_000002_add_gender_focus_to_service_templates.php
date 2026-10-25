<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gender moves onto the template, where the superadmin sets it once for every
 * salon, instead of living only on each salon's copy of the service.
 *
 * The backfill only adopts what the salons already agree on: a template every
 * live salon service tags with the same non-Unisex gender takes that gender.
 * Anything mixed, or untagged, stays Unisex for the superadmin to decide —
 * nothing is guessed from a template's name here.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('service_templates', function (Blueprint $table) {
            $table->enum('gender_focus', ['Unisex', 'Men Only', 'Women Only'])
                ->default('Unisex')
                ->after('estimated_duration_minutes');
        });

        $agreed = DB::table('services')
            ->whereNull('deleted_at')
            ->groupBy('template_id')
            ->havingRaw('COUNT(DISTINCT gender_focus) = 1')
            ->selectRaw('template_id, MIN(gender_focus) as gender_focus')
            ->get();

        foreach ($agreed as $row) {
            if ($row->gender_focus === 'Unisex') {
                continue;
            }

            DB::table('service_templates')
                ->where('id', $row->template_id)
                ->update(['gender_focus' => $row->gender_focus]);
        }
    }

    public function down(): void
    {
        Schema::table('service_templates', function (Blueprint $table) {
            $table->dropColumn('gender_focus');
        });
    }
};
