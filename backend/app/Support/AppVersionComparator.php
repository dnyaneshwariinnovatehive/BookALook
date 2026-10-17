<?php

namespace App\Support;

use App\Models\AppRelease;

class AppVersionComparator
{
    /**
     * Normalize version string (strips whitespace, leading 'v'/'V', and build/prerelease suffixes).
     */
    public static function normalizeVersion(string $version): string
    {
        $trimmed = trim($version);
        $clean = ltrim($trimmed, 'vV');
        $parts = preg_split('/[+-]/', $clean);
        return $parts[0] ?? $clean;
    }

    /**
     * Extract effective build number from parameter or '+build' suffix.
     */
    public static function extractBuildNumber(string $version, int $build): int
    {
        if ($build <= 0 && str_contains($version, '+')) {
            $parts = explode('+', $version);
            return (int) ($parts[1] ?? 0);
        }
        return $build;
    }

    /**
     * Compare two version + build number tuples.
     *
     * Returns:
     *  -1 if (v1, b1) < (v2, b2)
     *   0 if (v1, b1) == (v2, b2)
     *   1 if (v1, b1) > (v2, b2)
     */
    public static function compare(string $version1, int $build1, string $version2, int $build2): int
    {
        $v1 = self::normalizeVersion($version1);
        $v2 = self::normalizeVersion($version2);

        $vComp = version_compare($v1, $v2);
        if ($vComp !== 0) {
            return $vComp;
        }

        $b1 = self::extractBuildNumber($version1, $build1);
        $b2 = self::extractBuildNumber($version2, $build2);

        return $b1 <=> $b2;
    }

    /**
     * Compare two AppRelease instances.
     */
    public static function compareReleases(AppRelease $release1, AppRelease $release2): int
    {
        return self::compare(
            $release1->version,
            (int) $release1->build_number,
            $release2->version,
            (int) $release2->build_number
        );
    }

    public static function isLessThan(string $version1, int $build1, string $version2, int $build2): bool
    {
        return self::compare($version1, $build1, $version2, $build2) < 0;
    }

    public static function isGreaterThan(string $version1, int $build1, string $version2, int $build2): bool
    {
        return self::compare($version1, $build1, $version2, $build2) > 0;
    }

    public static function isEqual(string $version1, int $build1, string $version2, int $build2): bool
    {
        return self::compare($version1, $build1, $version2, $build2) === 0;
    }
}
