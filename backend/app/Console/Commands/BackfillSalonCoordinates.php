<?php

namespace App\Console\Commands;

use App\Models\Salon;
use Illuminate\Console\Command;

/**
 * Puts salons on the map that have never been pinned.
 *
 * Distance sorting is useless while every salon has null coordinates, and
 * waiting for several hundred owners to each open the app and tap a button is
 * not a plan. So an unpinned salon is placed at the centre of its own city:
 * wrong by a few kilometres, right by a few hundred, and enough to order a
 * list sensibly from day one.
 *
 * These are explicitly marked `city_centre`, never `owner`. The customer app
 * shows them as "about 4 km" rather than "4 km", and the moment an owner drops
 * a real pin it takes precedence and is never overwritten by this command.
 */
class BackfillSalonCoordinates extends Command
{
    protected $signature = 'app:backfill-salon-coordinates
        {--force : Also move salons that already sit at their city centre}
        {--dry-run : Show what would change without writing anything}';

    protected $description = 'Place unpinned salons at the centre of their city so distance sorting works';

    public function handle(): int
    {
        $dryRun = (bool) $this->option('dry-run');

        $salons = Salon::with('city')
            ->whereNotNull('city_id')
            ->when(
                $this->option('force'),
                // Never touches an owner's own pin, even with --force.
                fn ($q) => $q->where(fn ($w) => $w->whereNull('latitude')
                    ->orWhere('location_source', 'city_centre')),
                fn ($q) => $q->whereNull('latitude')->orWhereNull('longitude')
            )
            ->get();

        $placed = 0;
        $skipped = 0;

        foreach ($salons as $salon) {
            $city = $salon->city;

            if (! $city || $city->latitude === null || $city->longitude === null) {
                $this->components->twoColumnDetail(
                    $salon->name,
                    '<fg=yellow>skipped — ' . ($city->name ?? 'no city') . ' has no coordinates</>'
                );
                $skipped++;
                continue;
            }

            if (! $dryRun) {
                $salon->forceFill([
                    'latitude' => $city->latitude,
                    'longitude' => $city->longitude,
                    'location_source' => 'city_centre',
                ])->save();
            }

            $this->components->twoColumnDetail(
                $salon->name,
                "{$city->name} centre ({$city->latitude}, {$city->longitude})"
            );
            $placed++;
        }

        $this->newLine();

        if ($dryRun) {
            $this->components->warn("Dry run — nothing was written. {$placed} salon(s) would be placed.");

            return self::SUCCESS;
        }

        $this->components->info("Placed {$placed} salon(s) at their city centre.");

        if ($skipped > 0) {
            $this->components->warn(
                "{$skipped} salon(s) skipped: their city has no coordinates on record."
            );
        }

        $owned = Salon::where('location_source', 'owner')->count();
        $unplaced = Salon::whereNull('latitude')->count();

        $this->components->twoColumnDetail('pinned by their owner', (string) $owned);
        $this->components->twoColumnDetail('still unplaced', (string) $unplaced);

        return self::SUCCESS;
    }
}
