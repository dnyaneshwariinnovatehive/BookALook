<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where BookALook sends a salon's money.
 *
 * On the salon, because settlement is per salon (an owner with two salons may
 * bank them separately). Also on the website enquiry, because that is the only
 * record the landing-page form creates: the details travel to the salon when a
 * collaborator onboards it.
 *
 * Every column is nullable — registration and plan activation never wait on
 * them. The account number is stored encrypted (Laravel's `encrypted` cast),
 * hence `text`; only its last four digits are kept in the clear, for display.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->string('bank_account_holder_name', 150)->nullable();
            $table->string('bank_name', 150)->nullable();
            $table->text('bank_account_number')->nullable();
            $table->string('bank_account_last4', 4)->nullable();
            $table->string('bank_ifsc', 11)->nullable();
            $table->string('bank_upi_id', 100)->nullable();
            $table->timestamp('bank_details_updated_at')->nullable();
            $table->uuid('bank_details_updated_by')->nullable();
        });

        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->string('bank_account_holder_name', 150)->nullable();
            $table->string('bank_name', 150)->nullable();
            $table->text('bank_account_number')->nullable();
            $table->string('bank_account_last4', 4)->nullable();
            $table->string('bank_ifsc', 11)->nullable();
            $table->string('bank_upi_id', 100)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn([
                'bank_account_holder_name', 'bank_name', 'bank_account_number', 'bank_account_last4',
                'bank_ifsc', 'bank_upi_id', 'bank_details_updated_at', 'bank_details_updated_by',
            ]);
        });

        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->dropColumn([
                'bank_account_holder_name', 'bank_name', 'bank_account_number', 'bank_account_last4',
                'bank_ifsc', 'bank_upi_id',
            ]);
        });
    }
};
