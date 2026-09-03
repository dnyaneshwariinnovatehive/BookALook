<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('salon_enquiries', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('(UUID())'));
            $table->string('salon_name', 150);
            $table->string('owner_name', 150);
            $table->string('phone', 15);
            $table->string('city', 100)->nullable();
            $table->text('message')->nullable();
            $table->enum('status', ['new', 'assigned', 'onboarded', 'rejected'])->default('new');
            $table->uuid('assigned_collaborator_id')->nullable();
            $table->timestamp('assigned_at')->nullable();
            $table->timestamps();
            
            $table->foreign('assigned_collaborator_id')->references('id')->on('users')->onDelete('set null');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('salon_enquiries');
    }
};
