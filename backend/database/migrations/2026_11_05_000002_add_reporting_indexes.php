<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Indexes for the SuperAdmin analytics and money-in-pocket queries, which
 * filter by visit date, payment date and refund date and join payments and
 * refunds to their booking. PostgreSQL does not index foreign keys by itself,
 * so without these every report reads the whole table.
 */
return new class extends Migration
{
    private const INDEXES = [
        'appointments' => [
            'appointments_date_status_index' => ['appointment_date', 'status'],
            'appointments_customer_date_index' => ['customer_id', 'appointment_date'],
        ],
        'payments' => [
            'payments_appointment_status_index' => ['appointment_id', 'status'],
            'payments_paid_at_index' => ['paid_at'],
        ],
        'payment_refunds' => [
            'payment_refunds_appointment_index' => ['appointment_id'],
            'payment_refunds_created_at_index' => ['created_at'],
        ],
        'salon_payouts' => [
            'salon_payouts_status_distributed_index' => ['status', 'distributed_at'],
        ],
        'reviews' => [
            'reviews_created_at_index' => ['created_at'],
        ],
    ];

    public function up(): void
    {
        foreach (self::INDEXES as $table => $indexes) {
            foreach ($indexes as $name => $columns) {
                if (! Schema::hasIndex($table, $name)) {
                    Schema::table($table, fn (Blueprint $t) => $t->index($columns, $name));
                }
            }
        }
    }

    public function down(): void
    {
        foreach (self::INDEXES as $table => $indexes) {
            foreach (array_keys($indexes) as $name) {
                if (Schema::hasIndex($table, $name)) {
                    Schema::table($table, fn (Blueprint $t) => $t->dropIndex($name));
                }
            }
        }
    }
};
