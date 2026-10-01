<?php

namespace App\Support;

/**
 * Reduces a phone number a person typed to the shape WhatsApp will accept.
 *
 * Numbers arrive in every form: with a +91, with a leading 0, with spaces and
 * dashes, or as ten bare digits. Providers do not agree on which of those they
 * will route, and a number that is mangled silently does not fail loudly — it
 * goes to whoever the last few digits happen to belong to. So the shape is
 * normalised in one place and a number that cannot be made sense of returns null
 * rather than a guess.
 *
 * It lives in Support because three callers need it and none of them owns it: the
 * WhatsApp gateways, which must not guess, and the marketing audience builder,
 * which already had this logic inline.
 */
class PhoneNumber
{
    /** The shortest an international number can usefully be. */
    private const MIN_LENGTH = 11;

    /** E.164 caps subscriber numbers at 15 digits including the country code. */
    private const MAX_LENGTH = 15;

    /**
     * Country code and digits with no punctuation, or null when the input is not
     * a number this platform can route.
     *
     * @param  string|null  $countryCode  Overrides the configured default. Used by
     *                                    callers that know the number's origin.
     */
    public static function normalise(?string $phone, ?string $countryCode = null): ?string
    {
        if (! $phone) {
            return null;
        }

        $digits = preg_replace('/\D+/', '', $phone);

        if ($digits === '' || $digits === null) {
            return null;
        }

        $country = $countryCode ?: (string) config('services.whatsapp.default_country_code', '91');

        // 0XXXXXXXXXX — the domestic trunk prefix.
        if (strlen($digits) === 11 && str_starts_with($digits, '0')) {
            $digits = substr($digits, 1);
        }

        if (strlen($digits) === 10) {
            return $country.$digits;
        }

        if (strlen($digits) === 12 && str_starts_with($digits, $country)) {
            return $digits;
        }

        // Anything else is either already international or not a phone number;
        // accept plausible lengths and reject the rest.
        return strlen($digits) >= self::MIN_LENGTH && strlen($digits) <= self::MAX_LENGTH
            ? $digits
            : null;
    }

    /**
     * The same number with an explicit `+`, which is the form AISensy documents
     * as recommended.
     *
     * Returns null rather than `+` with nothing after it, so a caller cannot
     * accidentally put a bare `+` into a request body.
     */
    public static function international(?string $phone, ?string $countryCode = null): ?string
    {
        $digits = self::normalise($phone, $countryCode);

        return $digits === null ? null : '+'.$digits;
    }
}