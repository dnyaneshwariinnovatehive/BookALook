<?php

namespace App\Services\Notifications;

/**
 * The service-account key FCM needs, assembled from configuration.
 *
 * This exists so that "the FCM driver is selected but nobody configured it" is
 * a single, early, obvious failure rather than something discovered once per
 * notification per device, halfway through a queue worker. Nothing here reads a
 * file at construction time and nothing is ever logged — a private key that
 * reaches a log file has already lost.
 */
final class FcmCredentials
{
    public function __construct(
        public readonly string $projectId,
        public readonly string $clientEmail,
        public readonly string $privateKey,
    ) {
    }

    /**
     * Build from config, or explain precisely what is missing.
     *
     * Two shapes are supported, and a third is a consequence of supporting them:
     *
     *   - an inline PEM in FCM_PRIVATE_KEY, with FCM_PROJECT_ID and
     *     FCM_CLIENT_EMAIL alongside it;
     *   - a path to a service-account JSON on the server (FCM_CREDENTIALS_PATH),
     *     which supplies the key *and* the project id and client email, since all
     *     three live in the same file;
     *   - so also: a path plus overrides, for the server whose service account
     *     is named differently from the project it sends for.
     */
    public static function fromConfig(): self
    {
        $inlineKey = (string) (config('services.push.fcm.private_key') ?: '');
        $path = (string) (config('services.push.fcm.credentials_path') ?: '');

        // Whatever the file provided, the environment still wins. Someone who
        // typed FCM_PROJECT_ID into .env meant it, and silently preferring the
        // file would make the config look like it was being ignored.
        $projectId = (string) (config('services.push.fcm.project_id') ?: '');
        $clientEmail = (string) (config('services.push.fcm.client_email') ?: '');
        $privateKey = $inlineKey;

        if ($path !== '') {
            $file = self::readCredentialsFile($path);

            $privateKey = $privateKey === '' ? $file['private_key'] : $privateKey;
            $projectId = $projectId === '' ? $file['project_id'] : $projectId;
            $clientEmail = $clientEmail === '' ? $file['client_email'] : $clientEmail;
        }

        $missing = [];

        if ($projectId === '') {
            $missing[] = 'FCM_PROJECT_ID';
        }

        if ($clientEmail === '') {
            $missing[] = 'FCM_CLIENT_EMAIL';
        }

        if ($privateKey === '') {
            $missing[] = $path !== ''
                ? 'a private_key in the service-account file at FCM_CREDENTIALS_PATH'
                : 'FCM_PRIVATE_KEY or FCM_CREDENTIALS_PATH';
        }

        if ($missing !== []) {
            // Names only. Never the values, and never the key.
            throw new MissingFcmCredentials(
                'PUSH_DRIVER is set to "fcm" but the Firebase service account is not configured. '
                .'Missing: '.implode(', ', $missing)
                .'. Set PUSH_DRIVER=log to keep running without Firebase.'
            );
        }

        return new self($projectId, $clientEmail, self::normaliseKey($privateKey));
    }

    /**
     * Whether the fcm driver could be built, without building it.
     *
     * For a health check or an artisan command that should report rather than
     * throw. Never used on the delivery path: by the time a push is being sent,
     * unconfigured is a failure worth surfacing, not a condition to route around.
     */
    public static function areConfigured(): bool
    {
        try {
            self::fromConfig();

            return true;
        } catch (MissingFcmCredentials) {
            return false;
        }
    }

    /**
     * Read the three members this class needs out of a service-account file.
     *
     * @return array{private_key: string, project_id: string, client_email: string}
     */
    private static function readCredentialsFile(string $path): array
    {
        if (! is_readable($path)) {
            throw new MissingFcmCredentials(
                'FCM_CREDENTIALS_PATH points at a file this process cannot read. '
                .'Check the path and the permissions on the server.'
            );
        }

        $json = json_decode((string) file_get_contents($path), true);

        if (! is_array($json) || ! isset($json['private_key'])) {
            throw new MissingFcmCredentials(
                'The file at FCM_CREDENTIALS_PATH is not a Firebase service-account JSON '
                .'(no private_key member).'
            );
        }

        return [
            'private_key' => (string) $json['private_key'],
            'project_id' => (string) ($json['project_id'] ?? ''),
            'client_email' => (string) ($json['client_email'] ?? ''),
        ];
    }

    /**
     * An environment variable cannot hold a real newline, so keys pasted into
     * .env arrive with literal backslash-n sequences. An un-normalised key fails
     * inside OpenSSL with a message that says nothing about the cause.
     */
    private static function normaliseKey(string $key): string
    {
        return str_replace('\n', "\n", trim($key));
    }
}
