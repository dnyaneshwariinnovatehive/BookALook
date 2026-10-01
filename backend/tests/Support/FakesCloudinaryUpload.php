<?php

namespace Tests\Support;

use Cloudinary\Api\ApiResponse;
use Cloudinary\Cloudinary;

/**
 * Stand in for the Cloudinary upload API without leaving the test process.
 *
 * Invoices are uploaded through the SDK rather than the disk adapter, because
 * the adapter cannot express what a raw PDF needs. That means Storage::fake()
 * no longer intercepts the upload, and a test that forgets that will talk to the
 * real Cloudinary account named in .env. This binds a recorder in its place.
 *
 * The recorder is also returned so a test can assert what was handed over and
 * what options travelled with it.
 */
trait FakesCloudinaryUpload
{
    /**
     * The recorder built by fakeCloudinaryUpload(), or null if it was never used.
     *
     * Mockery's container fake is reset between tests, so the recorder object
     * itself is kept here for a later assertion to inspect.
     */
    protected ?object $cloudinaryUpload = null;

    protected function fakeCloudinaryUpload(?string $secureUrl = null): object
    {
        $recorder = new class($secureUrl)
        {
            public mixed $asset = null;

            public array $options = [];

            public string $body = '';

            public int $uploads = 0;

            public function __construct(private ?string $url) {}

            /** Mirrors UploadApi::upload(): a stream in, an ApiResponse out. */
            public function upload(mixed $asset, array $options = []): ApiResponse
            {
                $this->uploads++;
                $this->asset = $asset;
                $this->options = $options;
                $this->body = is_resource($asset) ? (string) stream_get_contents($asset) : '';

                $id = $options['public_id'] ?? 'unknown';
                $type = $options['resource_type'] ?? 'image';

                // Shaped like Cloudinary's: a raw file's public ID already
                // carries its extension, anything else gets its format appended.
                $path = $type === 'raw' ? $id : $id.'.'.($options['format'] ?? 'bin');

                return new ApiResponse([
                    'public_id' => $id,
                    'secure_url' => $this->url
                        ?? "https://res.cloudinary.com/demo/{$type}/upload/{$path}",
                ], []);
            }
        };

        $this->app->instance(
            Cloudinary::class,
            new class($recorder)
            {
                public function __construct(private object $recorder) {}

                public function uploadApi(): object
                {
                    return $this->recorder;
                }
            }
        );

        $this->cloudinaryUpload = $recorder;

        return $recorder;
    }
}
