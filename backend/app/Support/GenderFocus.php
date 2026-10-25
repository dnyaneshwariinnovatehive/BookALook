<?php

namespace App\Support;

/**
 * Who a service, template or salon is for, and the rules that tie them.
 *
 * The superadmin sets it on the template, which is the one record every salon
 * offering that service shares. A salon may narrow a Unisex template to one
 * gender but never contradict a gendered one, and the salon's own focus caps
 * whatever its services may be.
 *
 * Customers are matched against the effective audience: a gendered service is
 * for that gender wherever it is offered, and a Unisex one takes on the
 * salon's focus.
 */
final class GenderFocus
{
    public const UNISEX = 'Unisex';
    public const MEN = 'Men Only';
    public const WOMEN = 'Women Only';

    public const ALL = [self::UNISEX, self::MEN, self::WOMEN];

    /** Validation rule fragment for any field holding one of these. */
    public static function rule(): string
    {
        return 'in:'.implode(',', self::ALL);
    }

    /**
     * A customer-side audience — the `gender` filter (`men`/`women`), a profile
     * gender (`male`/`female`) or a focus value itself — as the focus it means.
     * Null when it means "everyone", which is the caller's cue not to filter.
     */
    public static function fromAudience(?string $value): ?string
    {
        return match (strtolower(trim((string) $value))) {
            'men', 'man', 'male', 'm', 'men only' => self::MEN,
            'women', 'woman', 'female', 'f', 'women only' => self::WOMEN,
            default => null,
        };
    }

    /** The focus values a given audience should see: Unisex plus their own. */
    public static function visibleTo(string $focus): array
    {
        return $focus === self::UNISEX ? self::ALL : [self::UNISEX, $focus];
    }

    /** Who a salon's service is really for, once the salon's own focus applies. */
    public static function effective(?string $serviceFocus, ?string $salonFocus): string
    {
        $serviceFocus = self::normalise($serviceFocus);

        return $serviceFocus !== self::UNISEX ? $serviceFocus : self::normalise($salonFocus);
    }

    /**
     * The values a salon may give its service of this template.
     *
     * A gendered template is locked to its gender. A Unisex one may stay
     * Unisex or be narrowed. A single-gender salon caps both, so a Women Only
     * salon gets nothing at all for a Men Only template.
     */
    public static function allowedFor(?string $templateFocus, ?string $salonFocus): array
    {
        $templateFocus = self::normalise($templateFocus);
        $salonFocus = self::normalise($salonFocus);

        if ($templateFocus !== self::UNISEX) {
            return in_array($salonFocus, [self::UNISEX, $templateFocus], true) ? [$templateFocus] : [];
        }

        return $salonFocus === self::UNISEX ? self::ALL : [$salonFocus];
    }

    /** What a salon's service of this template is when the owner does not say. */
    public static function defaultFor(?string $templateFocus, ?string $salonFocus): ?string
    {
        return self::allowedFor($templateFocus, $salonFocus)[0] ?? null;
    }

    /**
     * What a template's name suggests it is for, so the superadmin dashboard
     * can flag "Men's Haircut" sitting in the catalogue as Unisex. Only ever a
     * hint: nothing is changed on the strength of a name.
     */
    public static function suggestFromName(string $name): ?string
    {
        $name = strtolower($name);

        if (preg_match("/\b(women|womens|women's|ladies|lady|female|bridal|bride)\b/u", $name)) {
            return self::WOMEN;
        }

        if (preg_match("/\b(men|mens|men's|gents|gent|male|beard|moustache|mustache|groom)\b/u", $name)) {
            return self::MEN;
        }

        return null;
    }

    public static function normalise(?string $focus): string
    {
        return in_array($focus, self::ALL, true) ? $focus : self::UNISEX;
    }
}
