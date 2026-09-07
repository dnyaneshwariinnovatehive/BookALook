<?php

namespace App\Services\Payments;

use RuntimeException;

/** The provider could not be reached, or refused the request. */
class PaymentGatewayException extends RuntimeException
{
}
