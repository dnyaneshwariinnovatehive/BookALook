<?php

namespace App\Repositories;

use App\Models\NotificationTemplate;
use Illuminate\Support\Facades\Cache;

class NotificationTemplateRepository
{
    /**
     * Cache duration in seconds.
     * We cache for 24 hours since templates change rarely, and we invalidate on update.
     */
    private const CACHE_TTL = 86400;

    private const CACHE_PREFIX = 'notification_template_';

    public function findByKey(string $key): ?NotificationTemplate
    {
        $cacheKey = self::CACHE_PREFIX . $key;

        return Cache::remember($cacheKey, self::CACHE_TTL, function () use ($key) {
            return NotificationTemplate::where('key', $key)->first();
        });
    }

    public function all()
    {
        return NotificationTemplate::orderBy('type')->get();
    }

    public function update(NotificationTemplate $template, array $data): bool
    {
        $updated = $template->update($data);

        if ($updated) {
            $this->invalidateCache($template->key);
        }

        return $updated;
    }

    public function invalidateCache(string $key): void
    {
        Cache::forget(self::CACHE_PREFIX . $key);
    }
}
