<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One phone number, two separate accounts: a customer account (Customer app)
 * and a partner account (Partner app — salon owner, staff or collaborator).
 *
 * Phone and email were unique across every user, so a salon's staff member
 * could not book a haircut with their own number, and a customer could not
 * become a salon owner. They are now unique per account type instead. Inside
 * the partner side a number is still only one of owner, staff or
 * collaborator, because those three share the 'partner' account type.
 *
 * account_type is kept in step with role by the User model (see
 * User::accountTypeFor). SuperAdmin counts as 'partner': it is a platform
 * account, never a customer.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('account_type', 10)->default('customer')->after('role');
        });

        DB::table('users')->where('role', '!=', 'customer')->update(['account_type' => 'partner']);

        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique('users_phone_unique');
            $table->dropUnique('users_email_unique');
            $table->unique(['phone', 'account_type'], 'users_phone_account_type_unique');
            $table->unique(['email', 'account_type'], 'users_email_account_type_unique');
        });
    }

    /**
     * Only possible while no number or email is used on both sides; with such
     * pairs present, restoring the global unique index fails, as it should.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique('users_phone_account_type_unique');
            $table->dropUnique('users_email_account_type_unique');
            $table->unique('phone');
            $table->unique('email');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('account_type');
        });
    }
};
