<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Models\Appointment;
use Carbon\Carbon;

class MarkNoShowAppointments extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'app:mark-no-shows';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Marks scheduled appointments from previous days as no_show';

    /**
     * Execute the console command.
     */
    public function handle()
    {
        $count = Appointment::where('status', 'scheduled')
            ->whereDate('appointment_date', '<', Carbon::today())
            ->update([
                'status' => 'no_show',
                'no_show_at' => now(),
            ]);

        $this->info("Marked {$count} appointments as no-show.");
    }
}
