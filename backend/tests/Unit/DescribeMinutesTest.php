<?php

namespace Tests\Unit;

use App\Services\BookingPolicyService;
use PHPUnit\Framework\TestCase;

class DescribeMinutesTest extends TestCase
{
    public function test_policy_windows_read_naturally(): void
    {
        $this->assertSame('45 minutes', BookingPolicyService::describeMinutes(45));
        $this->assertSame('1 hour', BookingPolicyService::describeMinutes(60));
        $this->assertSame('1 hour 30 minutes', BookingPolicyService::describeMinutes(90));
        $this->assertSame('5 hours', BookingPolicyService::describeMinutes(300));
        $this->assertSame('1 day 1 hour', BookingPolicyService::describeMinutes(1500));
    }
}
