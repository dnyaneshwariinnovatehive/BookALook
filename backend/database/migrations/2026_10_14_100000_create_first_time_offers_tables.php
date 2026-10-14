<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. First-Time Offers Configuration Table
        Schema::create('first_time_offers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name', 150);
            $table->text('description')->nullable();
            
            // Scope: 'new_to_platform' | 'new_to_salon'
            $table->string('scope', 30)->index();
            
            // Discount type: 'percentage' | 'flat'
            $table->string('discount_type', 20);
            $table->decimal('discount_value', 10, 2);
            $table->decimal('max_discount_cap', 10, 2)->nullable();
            
            // Configurable minimum conditions (null = no minimum)
            $table->decimal('min_service_price', 10, 2)->nullable();
            $table->decimal('min_eligible_subtotal', 10, 2)->nullable();
            $table->decimal('min_total_booking_subtotal', 10, 2)->nullable();
            
            // Status and schedule
            $table->boolean('is_active')->default(true)->index();
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            
            // Platform & campaign redemption limits
            $table->unsignedInteger('max_redemptions')->nullable();
            $table->unsignedInteger('current_redemptions')->default(0);
            
            $table->timestamps();
            $table->softDeletes();
        });

        // 2. Explicit Eligible Service Templates Mapping (Global Catalogue definition)
        Schema::create('first_time_offer_services', function (Blueprint $table) {
            $table->foreignUuid('offer_id')->constrained('first_time_offers')->cascadeOnDelete();
            $table->foreignUuid('service_template_id')->constrained('service_templates')->cascadeOnDelete();
            $table->timestamps();

            $table->primary(['offer_id', 'service_template_id'], 'fto_services_primary');
        });

        // 3. Participating Salons Mapping
        Schema::create('first_time_offer_salons', function (Blueprint $table) {
            $table->foreignUuid('offer_id')->constrained('first_time_offers')->cascadeOnDelete();
            $table->foreignUuid('salon_id')->constrained('salons')->cascadeOnDelete();
            $table->timestamps();

            $table->primary(['offer_id', 'salon_id'], 'fto_salons_primary');
        });

        // 4. Offer Redemptions and Reservations Persistence
        Schema::create('first_time_offer_redemptions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('offer_id')->constrained('first_time_offers')->restrictOnDelete();
            $table->foreignUuid('customer_id')->constrained('users')->restrictOnDelete();
            $table->foreignUuid('salon_id')->constrained('salons')->restrictOnDelete();
            $table->foreignUuid('appointment_id')->nullable()->constrained('appointments')->nullOnDelete();
            
            // Status: 'reserved' | 'committed' | 'released'
            $table->string('status', 30)->index();
            
            // Concurrency protection: unique active entitlement key.
            // Populated while status is 'reserved' or 'committed'; set to NULL when 'released'.
            // PostgreSQL and SQLite enforce uniqueness among non-null values.
            $table->string('active_entitlement_key', 255)->nullable()->unique();
            
            $table->string('scope', 30);
            $table->decimal('discount_amount', 10, 2);
            
            $table->timestamp('reserved_at');
            $table->timestamp('committed_at')->nullable();
            $table->timestamp('released_at')->nullable();
            $table->string('release_reason', 255)->nullable();
            
            $table->timestamps();

            $table->index(['customer_id', 'status']);
            $table->index(['offer_id', 'status']);
        });

        // 5. Historical attribution fields on appointments
        Schema::table('appointments', function (Blueprint $table) {
            $table->foreignUuid('first_time_offer_id')->nullable()->constrained('first_time_offers')->nullOnDelete();
            $table->decimal('first_time_discount_amount', 12, 2)->default(0.00);
        });

        // 6. Historical line-item attribution on appointment_services
        Schema::table('appointment_services', function (Blueprint $table) {
            $table->decimal('first_time_discount_amount', 12, 2)->default(0.00);
        });
    }

    public function down(): void
    {
        Schema::table('appointment_services', function (Blueprint $table) {
            $table->dropColumn('first_time_discount_amount');
        });

        Schema::table('appointments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('first_time_offer_id');
            $table->dropColumn('first_time_discount_amount');
        });

        Schema::dropIfExists('first_time_offer_redemptions');
        Schema::dropIfExists('first_time_offer_salons');
        Schema::dropIfExists('first_time_offer_services');
        Schema::dropIfExists('first_time_offers');
    }
};
