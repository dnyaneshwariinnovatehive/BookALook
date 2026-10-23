<?php

namespace Database\Seeders;

use App\Models\AppRelease;
use App\Models\AppUpdatePolicy;
use Illuminate\Database\Seeder;

class AppReleaseSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        // 1. Baseline Customer App Release
        $customerRelease = AppRelease::firstOrCreate(
            [
                'app' => AppRelease::APP_CUSTOMER,
                'version' => '1.0.0',
                'build_number' => 1,
            ],
            [
                'status' => AppRelease::STATUS_PUBLISHED,
                'released_at' => now(),
                'release_notes' => 'Initial production release of BookALook Customer App.',
                'android_store_url' => 'https://play.google.com/store/apps/details?id=com.bookalook.customer',
                'ios_store_url' => 'https://apps.apple.com/app/bookalook/id0000000000',
            ]
        );

        // 2. Baseline Partner App Release
        $partnerRelease = AppRelease::firstOrCreate(
            [
                'app' => AppRelease::APP_PARTNER,
                'version' => '1.0.0',
                'build_number' => 1,
            ],
            [
                'status' => AppRelease::STATUS_PUBLISHED,
                'released_at' => now(),
                'release_notes' => 'Initial production release of BookALook Partner App.',
                'android_store_url' => 'https://play.google.com/store/apps/details?id=com.bookalook.partner',
                'ios_store_url' => 'https://apps.apple.com/app/bookalook-partner/id0000000000',
            ]
        );

        // 3. Baseline Customer Policy
        AppUpdatePolicy::firstOrCreate(
            ['app' => AppRelease::APP_CUSTOMER],
            [
                'latest_release_id' => $customerRelease->id,
                'minimum_release_id' => $customerRelease->id,
                'update_mode' => AppUpdatePolicy::MODE_OPTIONAL,
                'is_enforced' => false,
                'update_message' => 'A newer version of BookALook is available. Please update to enjoy the best booking experience!',
                'android_store_url' => 'https://play.google.com/store/apps/details?id=com.bookalook.customer',
                'ios_store_url' => 'https://apps.apple.com/app/bookalook/id0000000000',
            ]
        );

        // 4. Baseline Partner Policy
        AppUpdatePolicy::firstOrCreate(
            ['app' => AppRelease::APP_PARTNER],
            [
                'latest_release_id' => $partnerRelease->id,
                'minimum_release_id' => $partnerRelease->id,
                'update_mode' => AppUpdatePolicy::MODE_OPTIONAL,
                'is_enforced' => false,
                'update_message' => 'A newer version of BookALook Partner is available. Please update to access all new features and fixes!',
                'android_store_url' => 'https://play.google.com/store/apps/details?id=com.bookalook.partner',
                'ios_store_url' => 'https://apps.apple.com/app/bookalook-partner/id0000000000',
            ]
        );
    }
}
