<?php

namespace App\Services;

use App\Jobs\SendWhatsAppMessageJob;
use App\Services\Auth\LoginOtp;
use App\Services\Auth\OtpStore;
use App\Models\User;
use App\Models\WhatsappAutomation;
use App\Models\WhatsAppMessage;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Changing the phone number on an account, for every kind of user.
 *
 * The phone number is how people sign in — an OTP is sent to it — so it is
 * only ever changed to a number the person has just proved they hold. The
 * code is tied to both the account and the new number, so a code sent for one
 * change cannot be spent on another, and it is spent the moment it works.
 */
class PhoneChangeService
{
    private const CODE_MINUTES = 10;
    private const MAX_ATTEMPTS = 5;

    /** Digits with an optional leading +, spaces and dashes removed. */
    public function normalise(?string $phone): string
    {
        return preg_replace('/[\s\-()]/', '', (string) $phone);
    }

    /**
     * Check the new number can be used, and send it a code.
     *
     * @return string What to tell the person.
     */
    public function sendCode(User $user, string $phone): string
    {
        $phone = $this->assertUsable($user, $phone);

        $automation = WhatsappAutomation::where('key', 'whatsapp_otp')->first();
        $live = $automation && $automation->is_enabled && ! empty($automation->aisensy_campaign_name);

        // Same behaviour as sign-in: a real code over WhatsApp when the
        // automation is set up, the demo code otherwise — never in production.
        $code = $live
            ? str_pad((string) random_int(100000, 999999), 6, '0', STR_PAD_LEFT)
            : app(LoginOtp::class)->demoCode();

        if ($code === null) {
            throw ValidationException::withMessages([
                'phone' => 'Codes cannot be sent right now. Please try again later.',
            ]);
        }

        app(OtpStore::class)->issue($this->codeKey($user, $phone), $code, self::CODE_MINUTES);

        if (! $live) {
            return "OTP sent. For testing, use {$code}.";
        }

        $message = WhatsAppMessage::create([
            'to_phone' => $phone,
            'template' => $automation->key,
            'campaign' => $automation->aisensy_campaign_name,
            'payload' => ['parameters' => [$code]],
            'status' => WhatsAppMessage::STATUS_QUEUED,
            'category' => 'authentication',
        ]);
        \App\Support\SafeDispatch::afterCommit(new SendWhatsAppMessageJob($message->id), ['whatsapp_message_id' => $message->id]);

        return 'OTP sent to the new number on WhatsApp.';
    }

    /**
     * Check the code and, if it is right, move the account to the new number.
     */
    public function confirm(User $user, string $phone, string $code): User
    {
        $phone = $this->normalise($phone);
        // Checked and used up atomically (OtpStore): two requests with the
        // same code cannot both move the account.
        $result = app(OtpStore::class)->consume(
            $this->codeKey($user, $phone), $code, self::MAX_ATTEMPTS, self::CODE_MINUTES
        );

        match ($result) {
            OtpStore::OK => null,
            OtpStore::EXPIRED => throw ValidationException::withMessages([
                'otp' => 'That code has expired. Ask for a new one.',
            ]),
            OtpStore::BURNED => throw ValidationException::withMessages([
                'otp' => 'Too many wrong codes. Ask for a new one.',
            ]),
            default => throw ValidationException::withMessages(['otp' => 'That code is not right.']),
        };

        // Checked again here: the number may have been taken since the code
        // was sent. The unique index is the final word if two race.
        $phone = $this->assertUsable($user, $phone);

        try {
            DB::transaction(function () use ($user, $phone) {
                $user->phone = $phone;
                $user->save();
            });
        } catch (QueryException $e) {
            throw ValidationException::withMessages([
                'phone' => 'This number is already used by another account.',
            ]);
        }

        return $user->fresh();
    }

    private function assertUsable(User $user, string $phone): string
    {
        $phone = $this->normalise($phone);

        if (! preg_match('/^\+?[0-9]{10,14}$/', $phone)) {
            throw ValidationException::withMessages(['phone' => 'Enter a valid phone number.']);
        }

        if ($phone === $user->phone) {
            throw ValidationException::withMessages(['phone' => 'This is already your phone number.']);
        }

        if (User::where('phone', $phone)->where('id', '!=', $user->id)->exists()) {
            throw ValidationException::withMessages(['phone' => 'This number is already used by another account.']);
        }

        return $phone;
    }

    /** One code per account and new number: it cannot move anyone else. */
    private function codeKey(User $user, string $phone): string
    {
        return "otp:phone-change:{$user->id}:{$phone}";
    }
}
