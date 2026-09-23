<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Localities inside a city, and everyone who belongs to one.
 *
 * A city is too coarse to be useful. "Pune" covers a two-hour drive, so a
 * customer browsing by city sees salons they will never visit, and a
 * collaborator assigned by city may be sent across town. The sub-area is the
 * unit people actually think in — Kothrud, Bandra West, Koramangala.
 *
 * Three things happen here.
 *
 * The sub_areas table, owned by SuperAdmin and seeded for the cities already in
 * use so no dropdown is empty on the first day.
 *
 * A sub_area_id on everyone who has a place: customers, collaborators and
 * salons. Nullable, because 22 of 24 existing customers have never even set a
 * city and locking them out of their own accounts to backfill a field would be
 * a poor trade. New sign-ups are required to choose; old records are left to
 * fill themselves in over time.
 *
 * Real city and sub-area columns on salon_enquiries. That table stored its city
 * as free text — "navi mumbai" and "Pimpri Chinchwad" — which is why the
 * salon-approval screen could never match an enquiry against anything. The
 * existing rows are matched to real cities by name here; the string column
 * stays as written, since it is what the owner actually typed.
 */
return new class extends Migration
{
    /**
     * Starter localities for the cities that already have salons or enquiries.
     *
     * Not exhaustive and not meant to be — SuperAdmin adds to these. The point
     * is that nobody meets an empty dropdown on the day this ships.
     */
    private const SEED = [
        'Pune' => [
            'Aundh', 'Baner', 'Camp', 'Deccan Gymkhana', 'Hadapsar', 'Hinjewadi',
            'Karve Nagar', 'Katraj', 'Kharadi', 'Kondhwa', 'Koregaon Park',
            'Kothrud', 'Magarpatta', 'Pimple Saudagar', 'Shivajinagar',
            'Viman Nagar', 'Wakad', 'Wanowrie', 'Warje', 'Yerwada',
        ],
        'Mumbai' => [
            'Andheri East', 'Andheri West', 'Bandra East', 'Bandra West', 'Borivali',
            'Chembur', 'Colaba', 'Dadar', 'Goregaon', 'Juhu', 'Kandivali',
            'Lower Parel', 'Malad', 'Mulund', 'Powai', 'Santacruz', 'Vile Parle',
            'Worli',
        ],
        'Navi Mumbai' => [
            'Airoli', 'Belapur', 'Ghansoli', 'Kharghar', 'Kopar Khairane', 'Nerul',
            'Panvel', 'Sanpada', 'Seawoods', 'Turbhe', 'Vashi',
        ],
        'Bangalore' => [
            'Banashankari', 'Basavanagudi', 'BTM Layout', 'Electronic City', 'Hebbal',
            'HSR Layout', 'Indiranagar', 'Jayanagar', 'JP Nagar', 'Koramangala',
            'Malleshwaram', 'Marathahalli', 'MG Road', 'Rajajinagar', 'Whitefield',
            'Yelahanka',
        ],
        'Nashik' => [
            'Cidco', 'College Road', 'Deolali', 'Gangapur Road', 'Indira Nagar',
            'Nashik Road', 'Panchavati', 'Satpur',
        ],
        'Pimpri Chinchwad' => [
            'Akurdi', 'Bhosari', 'Chinchwad', 'Nigdi', 'Pimpri', 'Ravet', 'Wakad',
        ],
    ];

    public function up(): void
    {
        Schema::create('sub_areas', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('city_id')->constrained('cities')->onDelete('cascade');
            $table->string('name', 120);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            // Two "Kothrud"s in one city would make the dropdown a coin toss and
            // the collaborator matching meaningless.
            $table->unique(['city_id', 'name']);
            $table->index(['city_id', 'is_active']);
        });

        // Customers browse from one, collaborators are matched on theirs.
        Schema::table('users', function (Blueprint $table) {
            $table->uuid('sub_area_id')->nullable()->index();
        });

        Schema::table('salons', function (Blueprint $table) {
            $table->uuid('sub_area_id')->nullable()->index();
        });

        Schema::table('salon_enquiries', function (Blueprint $table) {
            if (!Schema::hasColumn('salon_enquiries', 'city_id')) {
                $table->uuid('city_id')->nullable()->index();
            }
            $table->uuid('sub_area_id')->nullable()->index();
        });

        $this->seedSubAreas();
        $this->resolveEnquiryCities();
    }

    private function seedSubAreas(): void
    {
        foreach (self::SEED as $cityName => $areas) {
            $cityId = DB::table('cities')
                ->whereRaw('lower(name) = ?', [strtolower($cityName)])
                ->value('id');

            if (! $cityId) {
                continue;
            }

            foreach ($areas as $name) {
                DB::table('sub_areas')->insert([
                    'id' => (string) Str::uuid(),
                    'city_id' => $cityId,
                    'name' => $name,
                    'is_active' => true,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }
    }

    /**
     * Point existing enquiries at the city they were always describing.
     *
     * Matched case-insensitively on the name the owner typed, which resolves
     * every row currently in the table. Anything that does not match is left
     * null rather than guessed at — a wrong city sends a collaborator to the
     * wrong side of the state.
     */
    private function resolveEnquiryCities(): void
    {
        if (!Schema::hasColumn('salon_enquiries', 'city')) {
            return;
        }

        foreach (DB::table('salon_enquiries')->whereNotNull('city')->get(['id', 'city']) as $enquiry) {
            $cityId = DB::table('cities')
                ->whereRaw('lower(name) = ?', [strtolower(trim($enquiry->city))])
                ->value('id');

            if ($cityId) {
                DB::table('salon_enquiries')->where('id', $enquiry->id)->update(['city_id' => $cityId]);
            }
        }
    }

    public function down(): void
    {
        Schema::table('salon_enquiries', function (Blueprint $table) {
            // city_id belongs to the 09_02 migration. Do not drop it here.
            $table->dropColumn('sub_area_id');
        });

        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn('sub_area_id');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('sub_area_id');
        });

        Schema::dropIfExists('sub_areas');
    }
};
