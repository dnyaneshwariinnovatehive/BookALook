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
        $pushTitle = $template ? $template->active_push_title : '';
        $pushMessage = $template ? $template->active_push_message : '';
        $pushImageUrl = $template ? $template->push_image_url : null;
        $actionConfig = $template ? $template->action_config : null;

        $title = $this->interpolate($title, $variables);
        $message = $this->interpolate($message, $variables);
        $pushTitle = $this->interpolate($pushTitle, $variables);
        $pushMessage = $this->interpolate($pushMessage, $variables);

        return [
            'title' => $title,
            'message' => $message,
            'push_title' => $pushTitle,
            'push_message' => $pushMessage,
            'push_image_url' => $pushImageUrl,
            'action_config' => $actionConfig,
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
