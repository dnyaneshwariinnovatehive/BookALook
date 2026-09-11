<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gives cities a position, and records how a salon got its own.
 *
 * A city filter answers "can I book here"; it cannot answer "which of these is
 * closest". For that the platform needs coordinates, and it had none: every
 * salon's latitude and longitude was null and nothing ever wrote them.
 *
 * City coordinates are the bootstrap. A salon that has not dropped its own pin
 * sits at the centre of its city, which is good enough to sort a list and
 * honest about being approximate — `location_source` says which it is, so the
 * app never presents a guess as a measurement.
 */
return new class extends Migration
{
    /**
     * City centres, used to place salons that have not pinned themselves and
     * to work out which market a coordinate belongs to.
     */
    private const CENTRES = [
        'Mumbai' => [19.0760, 72.8777],
        'Delhi' => [28.6139, 77.2090],
        'Bangalore' => [12.9716, 77.5946],
        'Pune' => [18.5204, 73.8567],
        'Hyderabad' => [17.3850, 78.4867],
        'Chennai' => [13.0827, 80.2707],
        'Kolkata' => [22.5726, 88.3639],
        'Ahmedabad' => [23.0225, 72.5714],
        'Nashik' => [19.9975, 73.7898],
        'Nagpur' => [21.1458, 79.0882],
        'Thane' => [19.2183, 72.9781],
        'Surat' => [21.1702, 72.8311],
        'Jaipur' => [26.9124, 75.7873],
        'Lucknow' => [26.8467, 80.9462],
        'Kanpur' => [26.4499, 80.3319],
        'Indore' => [22.7196, 75.8577],
        'Bhopal' => [23.2599, 77.4126],
        'Patna' => [25.5941, 85.1376],
        'Vadodara' => [22.3072, 73.1812],
        'Coimbatore' => [11.0168, 76.9558],
        'Chandigarh' => [30.7333, 76.7794],
        'Gurgaon' => [28.4595, 77.0266],
        'Gurugram' => [28.4595, 77.0266],
        'Noida' => [28.5355, 77.3910],
        'Navi Mumbai' => [19.0330, 73.0297],
        'Aurangabad' => [19.8762, 75.3433],
        'Kolhapur' => [16.7050, 74.2433],
        'Solapur' => [17.6599, 75.9064],
        'Amravati' => [20.9374, 77.7796],
        'Mysore' => [12.2958, 76.6394],
        'Visakhapatnam' => [17.6868, 83.2185],
        'Ludhiana' => [30.9010, 75.8573],
        'Agra' => [27.1767, 78.0081],
        'Varanasi' => [25.3176, 82.9739],
        'Rajkot' => [22.3039, 70.8022],
        'Madurai' => [9.9252, 78.1198],
        'Guwahati' => [26.1445, 91.7362],
        'Bhubaneswar' => [20.2961, 85.8245],
        'Dehradun' => [30.3165, 78.0322],
        'Goa' => [15.2993, 74.1240],
    ];

    public function up(): void
    {
        Schema::table('cities', function (Blueprint $table) {
            $table->decimal('latitude', 10, 7)->nullable()->after('state');
            $table->decimal('longitude', 10, 7)->nullable()->after('latitude');
        });

        foreach (self::CENTRES as $name => [$lat, $lng]) {
            DB::table('cities')
                ->where('name', $name)
                ->update(['latitude' => $lat, 'longitude' => $lng]);
        }

        Schema::table('salons', function (Blueprint $table) {
            // 'owner' once the salon drops its own pin, 'city_centre' while it
            // is only sitting where its city is, null when it has no position
            // at all. Distances off a city centre are indicative, not measured,
            // and the app has to be able to tell the difference.
            $table->string('location_source', 20)->nullable()->after('longitude');
        });

        // Anything that already had coordinates was put there deliberately.
        DB::table('salons')
            ->whereNotNull('latitude')
            ->whereNotNull('longitude')
            ->update(['location_source' => 'owner']);
    }

    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn('location_source');
        });

        Schema::table('cities', function (Blueprint $table) {
            $table->dropColumn(['latitude', 'longitude']);
        });
    }
};
