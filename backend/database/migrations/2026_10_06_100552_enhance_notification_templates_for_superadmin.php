<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('notification_templates', function (Blueprint $table) {
            $table->string('name', 100)->nullable()->after('key');
            $table->text('description')->nullable()->after('name');
            $table->string('category', 50)->nullable()->after('description');
            
            // Push specific overrides
            $table->string('default_push_title', 255)->nullable()->after('default_message');
            $table->text('default_push_message')->nullable()->after('default_push_title');
            
            $table->string('push_title', 255)->nullable()->after('message');
            $table->text('push_message')->nullable()->after('push_title');
            $table->string('push_image_url', 500)->nullable()->after('push_message');
            
            // Action and Schedule Configurations
            $table->jsonb('action_config')->nullable()->after('channels');
            $table->jsonb('schedule_config')->nullable()->after('action_config');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('notification_templates', function (Blueprint $table) {
            $table->dropColumn([
                'name',
                'description',
                'category',
                'default_push_title',
                'default_push_message',
                'push_title',
                'push_message',
                'push_image_url',
                'action_config',
                'schedule_config'
            ]);
        });
    }
};
