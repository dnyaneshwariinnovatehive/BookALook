<?php

namespace Database\Seeders;

use App\Models\City;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class CitySeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        $csvFile = fopen(__DIR__ . '/cities.csv', 'r');
        
        $firstLine = true;
        while (($data = fgetcsv($csvFile, 1000, ',')) !== FALSE) {
            if ($firstLine) {
                $firstLine = false;
                continue;
            }
            
            // Format: State,District,City,Population,Area,Latitude,Longitude
            $state = trim($data[0]);
            $cityName = trim($data[2]);
            
            City::firstOrCreate(
                ['name' => $cityName],
                ['state' => $state, 'is_active' => true]
            );
        }
        
        fclose($csvFile);
    }
}
