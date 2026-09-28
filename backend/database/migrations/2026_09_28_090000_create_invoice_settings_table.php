<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How the platform's invoices look.
 *
 * Deliberately a sibling of `platform_policy_settings` rather than a set of
 * keys inside it. Invoice branding is not a rule anybody is bound by — it is
 * artwork, and artwork is long: a registered address, a GSTIN line, terms and
 * conditions, a footer thank-you note. `platform_policy_settings.setting_value`
 * is a 255-character string, which is not enough room for a terms paragraph,
 * and widening a column that every policy read depends on is a much bigger
 * change than adding the table these deserve.
 *
 * Same key/value shape, same data_type cast, same "fall back to the default
 * until SuperAdmin overrides it" rule — so it reads like the table it sits
 * beside. Only the value is a `text`, because this is the one settings table
 * whose values are prose.
 */
return new class extends Migration {
    public function up(): void {
        Schema::create('invoice_settings', function (Blueprint $table) {
            $table->string('setting_key', 100)->primary();
            $table->text('setting_value')->nullable();
            $table->string('data_type', 20)->default('string');
            $table->text('description')->nullable();
            $table->foreignUuid('updated_by')->nullable()->constrained('users');
        });
    }
    public function down(): void { Schema::dropIfExists('invoice_settings'); }
};
