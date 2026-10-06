<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Models\Salon;
use App\Models\Appointment;
use App\Models\User;
use App\Models\WhatsAppMessage;
use App\Models\WhatsappAutomation;
use App\Jobs\SendWhatsAppMessageJob;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class SendAutomatedMessages extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'app:send-automated-messages';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Send 25-days reminders and birthday messages for salons that have them enabled';

    /**
     * Execute the console command.
     */
    public function handle()
    {
        $this->info('Starting automated messaging run...');
        
        // 1. Process 25 Days Reminders
        $this->process25DaysReminders();
        
        // 2. Process Birthday Messages
        $this->processBirthdayMessages();
        
        $this->info('Finished automated messaging run.');
    }
    
    private function process25DaysReminders()
    {
        $automation = WhatsappAutomation::where('key', 'whatsapp_25_day_reminder')->first();
        if (!$automation || !$automation->is_enabled || empty($automation->aisensy_campaign_name)) {
            $this->info('25-Days reminder automation is disabled or not fully configured.');
            return;
        }

        $targetDate = Carbon::now()->subDays(25)->toDateString();
        
        // Find all customers who had a completed appointment exactly 25 days ago
        // Use completed_at instead of appointment_date
        $appointments = Appointment::where('status', 'completed')
            ->whereNotNull('completed_at')
            ->whereDate('completed_at', $targetDate)
            ->whereNotNull('customer_id')
            ->with(['salon', 'customer'])
            ->get();
            
        $sentCount = 0;
        
        foreach ($appointments as $appointment) {
            $salon = $appointment->salon;
            $customer = $appointment->customer;
            
            if (!$customer || empty($customer->phone)) {
                continue;
            }

            // Dedupe check: one reminder per qualifying completed appointment.
            $recentlySent = DB::table('whatsapp_messages')
                ->where('related_appointment_id', $appointment->id)
                ->where('template', $automation->key)
                ->exists();
                
            if ($recentlySent) {
                continue;
            }
            
            $payloadParams = [
                $customer->first_name ?? $customer->name ?? 'Customer',
                $salon->name ?? 'our salon',
            ];

            $message = WhatsAppMessage::create([
                'user_id' => $customer->id,
                'to_phone' => $customer->phone,
                'recipient_phone' => $customer->phone, // some code uses to_phone, some uses recipient_phone. Using both to be safe depending on DB schema.
                'related_salon_id' => $salon->id,
                'related_appointment_id' => $appointment->id,
                'template' => $automation->key,
                'campaign' => $automation->aisensy_campaign_name,
                'payload' => ['parameters' => $payloadParams],
                'status' => WhatsAppMessage::STATUS_QUEUED,
                'category' => 'marketing',
            ]);
            
            SendWhatsAppMessageJob::dispatch($message->id);
            $sentCount++;
        }
        
        $this->info("Processed 25-days reminders. Sent: {$sentCount}");
    }
    
    private function processBirthdayMessages()
    {
        $automation = WhatsappAutomation::where('key', 'whatsapp_customer_birthday')->first();
        if (!$automation || !$automation->is_enabled || empty($automation->aisensy_campaign_name)) {
            $this->info('Birthday automation is disabled or not fully configured.');
            return;
        }

        $today = Carbon::now();
        $month = $today->format('m');
        $day = $today->format('d');
        $year = $today->year;
        
        // Find all customers whose birthday is today
        $birthdayUsers = User::whereMonth('dob', $month)
            ->whereDay('dob', $day)
            ->where('role', 'customer')
            ->get();
            
        $sentCount = 0;
        
        foreach ($birthdayUsers as $user) {
            if (empty($user->phone)) {
                continue;
            }

            // Dedupe: one message per customer per year
            // Stable customer identity + year
            $alreadySent = DB::table('whatsapp_messages')
                ->where('user_id', $user->id)
                ->where('template', $automation->key)
                ->whereYear('created_at', $year)
                ->exists();
                
            if ($alreadySent) {
                continue;
            }

            // A customer might visit multiple salons, we need to pick one for the salon_name variable
            // Usually the most recently visited salon makes the most sense.
            $lastAppointment = Appointment::where('customer_id', $user->id)
                ->where('status', 'completed')
                ->latest('completed_at')
                ->with('salon')
                ->first();

            $salonName = $lastAppointment && $lastAppointment->salon ? $lastAppointment->salon->name : 'BookALook';
            
            $payloadParams = [
                $user->first_name ?? $user->name ?? 'Customer',
                $salonName,
            ];

            $message = WhatsAppMessage::create([
                'user_id' => $user->id,
                'to_phone' => $user->phone,
                'recipient_phone' => $user->phone,
                'related_salon_id' => $lastAppointment ? $lastAppointment->salon_id : null,
                'template' => $automation->key,
                'campaign' => $automation->aisensy_campaign_name,
                'payload' => ['parameters' => $payloadParams],
                'status' => WhatsAppMessage::STATUS_QUEUED,
                'category' => 'marketing',
            ]);
            
            SendWhatsAppMessageJob::dispatch($message->id);
            $sentCount++;
        }
        
        $this->info("Processed birthday messages. Sent: {$sentCount}");
    }
}
