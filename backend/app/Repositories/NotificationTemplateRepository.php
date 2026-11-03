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
    public function findByKey(string $key): ?NotificationTemplate
    {
        return \App\Support\AppCache::remember(\App\Support\CacheKeys::template($key), \App\Support\CacheKeys::TTL_TEMPLATE, function () use ($key) {
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
        \App\Support\AppCache::forget(\App\Support\CacheKeys::template($key));
    }
}
