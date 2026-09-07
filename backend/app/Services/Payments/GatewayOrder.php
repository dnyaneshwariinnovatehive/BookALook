<?php

namespace App\Services\Payments;

/**
 * An order opened with the provider, ready to be paid.
 */
class GatewayOrder
{
    public function __construct(
        public readonly string $id,
        public readonly int $amountInPaise,
        public readonly string $currency,
        public readonly string $gateway,
        public readonly array $raw = [],
    ) {
    }

    public function amountInRupees(): float
    {
        return round($this->amountInPaise / 100, 2);
    }
}
