<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Models\Salon;
use App\Models\Appointment;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

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
        $targetDate = Carbon::now()->subDays(25)->toDateString();
        
        // Find all customers who had a completed appointment exactly 25 days ago
        // and where the salon has the toggle enabled.
        $appointments = Appointment::where('status', 'completed')
            ->whereDate('appointment_date', $targetDate)
            ->whereNotNull('customer_id')
            ->whereHas('salon', function($q) {
                $q->where('whatsapp_25_days_enabled', true);
            })
            ->with(['salon', 'customer'])
            ->get();
            
        $sentCount = 0;
        
        foreach ($appointments as $appointment) {
            $salon = $appointment->salon;
            $customer = $appointment->customer;
            
            // Dedupe check: ensure we haven't already sent a 25 day reminder to this customer for this salon recently
            $recentlySent = DB::table('whatsapp_messages')
                ->where('related_salon_id', $salon->id)
                ->where('recipient_phone', $customer->phone ?? '')
                ->where('template', '25_days_reminder')
                ->whereDate('created_at', '>', Carbon::now()->subDays(20))
                ->exists();
                
            if ($recentlySent || empty($customer->phone)) {
                continue;
            }
            
            // Log the message as sent for analytics
            DB::table('whatsapp_messages')->insert([
                'id' => Str::uuid(),
                'related_salon_id' => $salon->id,
                'recipient_phone' => $customer->phone,
                'template' => '25_days_reminder',
                'category' => 'marketing', // or utility, depending on Meta approval
                'sent_at' => Carbon::now(),
                'created_at' => Carbon::now(),
                'updated_at' => Carbon::now(),
            ]);
            
            $sentCount++;
            
            // NOTE: The actual integration with Meta/AISensy goes here.
            // As requested, the template isn't created yet and should not include the salon name.
            // For now, we simulate the send by tracking it in our database.
        }
        
        $this->info("Processed 25-days reminders. Sent: {$sentCount}");
    }
    
    private function processBirthdayMessages()
    {
        $today = Carbon::now();
        $month = $today->format('m');
        $day = $today->format('d');
        
        // Find all customers whose birthday is today
        $birthdayUsers = User::whereMonth('dob', $month)
            ->whereDay('dob', $day)
            ->where('role', 'customer')
            ->get();
            
        $sentCount = 0;
        
        foreach ($birthdayUsers as $user) {
            // Find which salons this user visits that have birthdays enabled
            $salonIds = Appointment::where('customer_id', $user->id)
                ->where('status', 'completed')
                ->select('salon_id')
                ->distinct()
                ->pluck('salon_id');
                
            $enabledSalons = Salon::whereIn('id', $salonIds)
                ->where('whatsapp_birthday_enabled', true)
                ->get();
                
            foreach ($enabledSalons as $salon) {
                // Dedupe: only 1 birthday message per year per salon
                $alreadySent = DB::table('whatsapp_messages')
                    ->where('related_salon_id', $salon->id)
                    ->where('recipient_phone', $user->phone ?? '')
                    ->where('template', 'birthday_message')
                    ->whereYear('created_at', $today->year)
                    ->exists();
                    
                if ($alreadySent || empty($user->phone)) {
                    continue;
                }
                
                // Log message
                DB::table('whatsapp_messages')->insert([
                    'id' => Str::uuid(),
                    'related_salon_id' => $salon->id,
                    'recipient_phone' => $user->phone,
                    'template' => 'birthday_message',
                    'category' => 'marketing',
                    'sent_at' => Carbon::now(),
                    'created_at' => Carbon::now(),
                    'updated_at' => Carbon::now(),
                ]);
                
                $sentCount++;
                // NOTE: Trigger actual WhatsApp send here when template is ready.
            }
        }
        
        $this->info("Processed birthday messages. Sent: {$sentCount}");
    }
}
