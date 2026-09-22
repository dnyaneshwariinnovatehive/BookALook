<?php

namespace App\Services\Marketing;

use App\Models\MarketingConsent;
use App\Models\Salon;
use App\Models\SubscriptionPlan;
use Illuminate\Support\Facades\DB;

/**
 * Turns "who should hear this" into a list of people.
 *
 * A salon's customers are not one list. Some booked through the app and have an
 * account; some walked in and exist only as a name and a number written on an
 * appointment. Both are customers, both can be messaged, and any segment that
 * quietly dropped the walk-ins would be wrong in a way nobody would notice
 * until a salon asked why its best customer never got the offer.
 *
 * So every segment is built over completed appointments — the one place both
 * kinds of customer meet — and the phone number, not the user id, is the
 * identity that matters.
 */
class AudienceBuilder
{
    public function __construct(private MarketingSettings $settings)
    {
    }

    public const SEGMENT_ALL = 'all';
    public const SEGMENT_REPEAT = 'repeat';
    public const SEGMENT_INACTIVE = 'inactive';
    public const SEGMENT_HIGH_VALUE = 'high_value';
    public const SEGMENT_SERVICE = 'service';
    public const SEGMENT_BIRTHDAY = 'birthday';
    public const SEGMENT_AREA = 'area';

    /**
     * Segments, what they mean, and what a plan must have to use them.
     *
     * @return array<int, array<string, mixed>>
     */
    public function catalogue(): array
    {
        return [
            [
                'key' => self::SEGMENT_ALL,
                'name' => 'All customers',
                'description' => 'Everyone who has completed a visit here.',
                'requires' => null,
            ],
            [
                'key' => self::SEGMENT_REPEAT,
                'name' => 'Repeat customers',
                'description' => sprintf('Customers with %d or more completed visits.', $this->settings->repeatVisits()),
                'requires' => 'segmentation',
            ],
            [
                'key' => self::SEGMENT_INACTIVE,
                'name' => 'Customers who have not been back',
                'description' => sprintf('No visit in the last %d days.', $this->settings->inactiveDays()),
                'requires' => 'segmentation',
            ],
            [
                'key' => self::SEGMENT_HIGH_VALUE,
                'name' => 'High-value customers',
                'description' => sprintf('Lifetime spend of ₹%s or more.', number_format($this->settings->highValueMinSpend())),
                'requires' => 'high_value_targeting',
            ],
            [
                'key' => self::SEGMENT_SERVICE,
                'name' => 'Customers of a particular service',
                'description' => 'Anyone who has booked the service you choose.',
                'requires' => 'service_targeting',
            ],
            [
                'key' => self::SEGMENT_BIRTHDAY,
                'name' => 'Birthdays',
                'description' => 'Customers with a birthday in the window you pick. Only customers with an account have a birth date on file.',
                'requires' => 'segmentation',
            ],
            [
                'key' => self::SEGMENT_AREA,
                'name' => 'Customers in an area',
                'description' => 'Customers whose saved area matches the one you choose.',
                'requires' => 'segmentation',
            ],
        ];
    }

    /** Whether a plan may use a segment. */
    public function isAllowed(string $segment, ?SubscriptionPlan $plan): bool
    {
        $entry = collect($this->catalogue())->firstWhere('key', $segment);

        if (! $entry) {
            return false;
        }

        return match ($entry['requires']) {
            null => true,
            'segmentation' => (bool) ($plan->has_customer_segmentation ?? false),
            'service_targeting' => (bool) ($plan->has_service_based_targeting ?? false),
            'high_value_targeting' => (bool) ($plan->has_high_value_targeting ?? false),
            default => false,
        };
    }

    /**
     * Build the list.
     *
     * @param  array<string, mixed>  $audience  {segment, service_id?, combo_id?,
     *                                          sub_area_id?, days?, birthday_window?}
     * @return \Illuminate\Support\Collection<int, object{phone:string,name:?string,user_id:?string,visits:int,spend:float,last_visit:?string}>
     */
    public function build(Salon $salon, array $audience)
    {
        $segment = $audience['segment'] ?? self::SEGMENT_ALL;

        // One row per person, aggregated over their completed visits here.
        // COALESCE is what lets an account customer and a walk-in sit in the
        // same result: whichever identity the appointment carried, the phone is
        // the key.
        $query = DB::table('appointments as a')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereNotNull(DB::raw('COALESCE(u.phone, a.walk_in_customer_phone)'))
            ->groupBy(DB::raw('COALESCE(u.phone, a.walk_in_customer_phone)'))
            ->select([
                DB::raw('COALESCE(u.phone, a.walk_in_customer_phone) as phone'),
                DB::raw('MAX(COALESCE(u.name, a.walk_in_customer_name)) as name'),
                DB::raw('MAX(a.customer_id) as user_id'),
                DB::raw('COUNT(*) as visits'),
                DB::raw('COALESCE(SUM(COALESCE(a.final_billed_amount, a.total_amount)), 0) as spend'),
                DB::raw('MAX(a.appointment_date) as last_visit'),
            ]);

        $this->applySegment($query, $salon, $segment, $audience);

        $rows = $query->get();

        // Applied after grouping because they are properties of the person, not
        // of any one visit.
        $rows = $this->applyAggregateFilters($rows, $segment, $audience);

        return $rows->map(function ($row) {
            $row->phone = $this->normalisePhone($row->phone);

            return $row;
        })->filter(fn ($row) => $row->phone !== null)
            // Two appointments can carry the same number under different
            // spellings; normalising can collapse them, so dedupe after.
            ->unique('phone')
            ->values();
    }

    /**
     * Who of these may actually be sent to.
     *
     * Kept separate from building so the partner app can show "240 customers,
     * 12 of whom have opted out" rather than a single unexplained number.
     *
     * @return array{reachable: \Illuminate\Support\Collection, skipped: array<string, int>}
     */
    public function screenForConsent($rows): array
    {
        $phones = $rows->pluck('phone')->all();

        $consents = MarketingConsent::whereIn('phone', $phones)
            ->pluck('status', 'phone');

        $requireOptIn = $this->settings->requiresExplicitOptIn();
        $skipped = [];
        $reachable = collect();

        foreach ($rows as $row) {
            $status = $consents[$row->phone] ?? null;

            if ($status === MarketingConsent::STATUS_OUT) {
                $row->skip_reason = 'opted_out';
                $skipped['opted_out'] = ($skipped['opted_out'] ?? 0) + 1;

                continue;
            }

            // With explicit opt-in required, silence is not consent.
            if ($requireOptIn && $status !== MarketingConsent::STATUS_IN) {
                $row->skip_reason = 'no_consent';
                $skipped['no_consent'] = ($skipped['no_consent'] ?? 0) + 1;

                continue;
            }

            $reachable->push($row);
        }

        return ['reachable' => $reachable->values(), 'skipped' => $skipped];
    }

    private function applySegment($query, Salon $salon, string $segment, array $audience): void
    {
        switch ($segment) {
            case self::SEGMENT_SERVICE:
                $serviceId = $audience['service_id'] ?? null;
                $comboId = $audience['combo_id'] ?? null;

                $query->whereExists(function ($sub) use ($serviceId, $comboId) {
                    $sub->selectRaw(1)
                        ->from('appointment_services as s')
                        ->whereColumn('s.appointment_id', 'a.id');

                    if ($serviceId) {
                        $sub->where('s.service_id', $serviceId);
                    }

                    if ($comboId) {
                        $sub->where('s.combo_id', $comboId);
                    }
                });
                break;

            case self::SEGMENT_AREA:
                if ($areaId = $audience['sub_area_id'] ?? null) {
                    $query->where('u.sub_area_id', $areaId);
                }
                break;

            case self::SEGMENT_BIRTHDAY:
                // Only account holders have a birth date; a walk-in never will.
                $query->whereNotNull('u.date_of_birth');
                $this->applyBirthdayWindow($query, (int) ($audience['birthday_window'] ?? 7));
                break;
        }
    }

    /**
     * Birthdays falling in the next N days, ignoring the year.
     *
     * Done with string comparison on the month-day because the column is a
     * plain date and both SQLite and MySQL can compare 'MM-DD' lexically. The
     * wrap around new year is why this is two conditions rather than a range.
     */
    private function applyBirthdayWindow($query, int $days): void
    {
        $from = now()->format('m-d');
        $to = now()->addDays(max(0, $days))->format('m-d');

        $driver = DB::connection()->getDriverName();
        $monthDay = match ($driver) {
            'sqlite' => "strftime('%m-%d', u.date_of_birth)",
            'pgsql' => "TO_CHAR(u.date_of_birth, 'MM-DD')",
            default => "DATE_FORMAT(u.date_of_birth, '%m-%d')",
        };

        if ($from <= $to) {
            $query->whereRaw("{$monthDay} BETWEEN ? AND ?", [$from, $to]);

            return;
        }

        // The window crosses into January.
        $query->where(function ($q) use ($monthDay, $from, $to) {
            $q->whereRaw("{$monthDay} >= ?", [$from])
                ->orWhereRaw("{$monthDay} <= ?", [$to]);
        });
    }

    private function applyAggregateFilters($rows, string $segment, array $audience)
    {
        return match ($segment) {
            self::SEGMENT_REPEAT => $rows->filter(
                fn ($row) => $row->visits >= (int) ($audience['visits'] ?? $this->settings->repeatVisits())
            ),

            self::SEGMENT_INACTIVE => $rows->filter(function ($row) use ($audience) {
                $days = (int) ($audience['days'] ?? $this->settings->inactiveDays());

                return $row->last_visit
                    && \Illuminate\Support\Carbon::parse($row->last_visit)->lt(now()->subDays($days));
            }),

            self::SEGMENT_HIGH_VALUE => $rows->filter(
                fn ($row) => (float) $row->spend >= (float) ($audience['min_spend'] ?? $this->settings->highValueMinSpend())
            ),

            default => $rows,
        };
    }

    /**
     * To the shape WhatsApp wants: country code, digits, no punctuation.
     *
     * Indian numbers are stored here in every form a person might type one —
     * with a +91, with a leading 0, with spaces. A number that cannot be made
     * sense of returns null and is reported as unusable rather than sent to
     * whoever the mangled digits happen to belong to.
     */
    public function normalisePhone(?string $phone): ?string
    {
        if (! $phone) {
            return null;
        }

        $digits = preg_replace('/\D+/', '', $phone);
        $country = (string) config('services.whatsapp.default_country_code', '91');

        if ($digits === '') {
            return null;
        }

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
        return strlen($digits) >= 11 && strlen($digits) <= 15 ? $digits : null;
    }
}
