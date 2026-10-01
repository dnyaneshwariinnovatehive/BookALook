<?php

namespace Tests;

use Cloudinary\Cloudinary;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        $this->refuseUnfakedCloudinary();
    }

    /**
     * Stand a refusing Cloudinary client in front of every test.
     *
     * The invoice PDF goes up through the SDK, which Storage::fake() does not
     * intercept, and with the sync queue any booking test runs that upload
     * inline. phpunit.xml already swaps in dummy credentials; this makes sure no
     * request is even attempted, so a test that forgets to fake the upload gets
     * a clear failure instead of a network call. FakesCloudinaryUpload replaces
     * this binding for the tests that want an upload to succeed.
     */
    private function refuseUnfakedCloudinary(): void
    {
        $this->app->instance(Cloudinary::class, new class
        {
            public function __call(string $method, array $arguments): never
            {
                throw new \RuntimeException(
                    "Cloudinary::{$method}() was called without being faked. "
                    .'Use Tests\Support\FakesCloudinaryUpload.'
                );
            }
        });
    }
}
