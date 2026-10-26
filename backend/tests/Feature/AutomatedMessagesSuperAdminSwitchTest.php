<?php

namespace Tests\Feature;

use App\Jobs\SendWhatsAppMessageJob;
use App\Models\Appointment;
use App\Models\Salon;
use App\Models\User;
use App\Models\WhatsappAutomation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The 25-day reminder and the birthday message are BookALook's own messages.
 * SuperAdmin's switch alone decides whether they go out; nothing a salon owner
 * does can turn them on or off.
 */
class AutomatedMessagesSuperAdminSwitchTest extends TestCase
{
    use RefreshDatabase;

    private User $customer;

    protected function setUp(): void
    {
        parent::setUp();
        Queue::fake();

        $owner = User::create(['role' => 'admin', 'name' => 'Owner', 'phone' => '9820002001', 'password_hash' => 'x']);
        $salon = Salon::create([
            'admin_id' => $owner->id, 'name' => 'Switch Salon', 'slug' => 'switch-'.Str::random(6),
            'address' => 'Pune', 'status' => 'active', 'submitted_by' => $owner->id,
        ]);

        $this->customer = User::create([
            'role' => 'customer', 'name' => 'Priya', 'phone' => '9820002002', 'password_hash' => 'x',
            'date_of_birth' => now()->subYears(25)->toDateString(),
        ]);

        $staff = User::create(['role' => 'service_provider', 'name' => 'Asha', 'phone' => '9820002003', 'password_hash' => 'x']);
        $provider = \App\Models\ServiceProvider::create(['user_id' => $staff->id, 'salon_id' => $salon->id, 'is_active' => true]);

        Appointment::create([
            'salon_id' => $salon->id, 'customer_id' => $this->customer->id, 'booking_source' => 'online',
            'appointed_provider_id' => $provider->id,
            'appointment_date' => now()->subDays(25)->toDateString(),
            'start_time' => '10:00:00', 'end_time' => '10:30:00',
            'status' => 'completed', 'completed_at' => now()->subDays(25), 'total_amount' => 500,
        ]);
    }

    private function automation(string $key, bool $enabled): void
    {
        WhatsappAutomation::updateOrCreate(['key' => $key], [
            'name' => $key, 'description' => $key, 'audience' => 'customer', 'frequency_label' => 'daily', 'is_enabled' => $enabled, 'aisensy_campaign_name' => "campaign_{$key}",
        ]);
    }

    private function queuedTemplates(): array
    {
        return \App\Models\WhatsAppMessage::pluck('template')->all();
    }

    public function test_nothing_is_sent_while_superadmin_has_both_switched_off(): void
    {
        $this->automation('whatsapp_25_day_reminder', false);
        $this->automation('whatsapp_customer_birthday', false);

        $this->artisan('app:send-automated-messages')->assertSuccessful();

        $this->assertSame([], $this->queuedTemplates());
        // Booking a visit in setUp nudges the salon's partner apps; that is not a message.
        Queue::assertNotPushed(SendWhatsAppMessageJob::class);
    }

    public function test_both_are_sent_once_superadmin_switches_them_on(): void
    {
        $this->automation('whatsapp_25_day_reminder', true);
        $this->automation('whatsapp_customer_birthday', true);

        $this->artisan('app:send-automated-messages')->assertSuccessful();

        $this->assertEqualsCanonicalizing(
            ['whatsapp_25_day_reminder', 'whatsapp_customer_birthday'],
            $this->queuedTemplates(),
        );
        Queue::assertPushed(SendWhatsAppMessageJob::class, 2);
    }

    public function test_each_switch_works_on_its_own(): void
    {
        $this->automation('whatsapp_25_day_reminder', true);
        $this->automation('whatsapp_customer_birthday', false);

        $this->artisan('app:send-automated-messages')->assertSuccessful();

        $this->assertSame(['whatsapp_25_day_reminder'], $this->queuedTemplates());
    }

    public function test_salon_owners_have_no_messaging_settings_any_more(): void
    {
        $owner = User::where('role', 'admin')->first();
        $salonId = Salon::first()->id;

        $this->actingAs($owner, 'sanctum')->getJson("/api/partner/salons/{$salonId}/automated-messaging")->assertNotFound();
        $this->actingAs($owner, 'sanctum')->putJson("/api/partner/salons/{$salonId}/automated-messaging", [])->assertNotFound();
    }
}
