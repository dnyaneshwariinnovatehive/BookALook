<?php

namespace App\Services\Notifications;

use RuntimeException;

/**
 * Raised when `PUSH_DRIVER=fcm` is selected without a usable service account.
 *
 * Its own file because PSR-4 autoloading is one class per file: declaring it
 * alongside FcmCredentials works only for callers that happen to have loaded
 * FcmCredentials first, and a `catch (MissingFcmCredentials)` in a test that
 * never referenced the real class would fatal with "class not found" instead of
 * catching the thing it was written to catch.
 *
 * A dedicated class also lets AppServiceProvider and the tests react to a
 * misconfigured driver specifically, without matching on a message string.
 */
class MissingFcmCredentials extends RuntimeException
{
}
