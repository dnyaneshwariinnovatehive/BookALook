<?php

namespace App\Services\Notifications;

use App\Repositories\NotificationTemplateRepository;

class NotificationTemplateResolver
{
    public function __construct(private NotificationTemplateRepository $repository)
    {
    }

    /**
     * Resolve the template and interpolate variables.
     * Returns null if the template is disabled.
     */
    public function resolve(string $key, array $variables = []): ?array
    {
        $template = $this->repository->findByKey($key);

        if ($template && !$template->is_enabled) {
            return null; // Template is explicitly disabled
        }

        $title = $template ? $template->active_title : '';
        $message = $template ? $template->active_message : '';

        // If template doesn't exist, we fallback to an empty string here,
        // but normally the seeder ensures it exists. The callers should
        // still provide a fallback in their codebase if needed, or we just
        // rely on the DB. Let's do interpolation.

        $title = $this->interpolate($title, $variables);
        $message = $this->interpolate($message, $variables);

        return [
            'title' => $title,
            'message' => $message,
            'template' => $template,
        ];
    }

    private function interpolate(string $text, array $variables): string
    {
        foreach ($variables as $key => $value) {
            $text = str_replace('{{' . $key . '}}', (string)$value, $text);
        }
        
        // Remove unresolved variables to prevent "Your appointment at {{salon_name}}"
        $text = preg_replace('/\{\{[^\}]+\}\}/', '', $text);

        return $text;
    }
}
