<?php

namespace App\Services;

use App\Models\Salon;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * A salon's bank details: where BookALook sends the money it collected for it.
 *
 * Optional everywhere — registration, onboarding and plan activation never
 * wait on them — but needed before a settlement can be paid. One place for the
 * rules, the clean-up and the masking, so the Partner app, the collaborator
 * onboarding, the website form and the admin panel all behave the same.
 *
 * The "required" set is the four fields a bank transfer needs. UPI is extra.
 */
class BankDetailsService
{
    /** Request keys, as every client sends them. */
    public const FIELDS = [
        'bank_account_holder_name',
        'bank_name',
        'bank_account_number',
        'bank_ifsc',
        'bank_upi_id',
    ];

    /** What a transfer needs. */
    public const REQUIRED = [
        'bank_account_holder_name',
        'bank_name',
        'bank_account_number',
        'bank_ifsc',
    ];

    /**
     * Validation for the bank fields. Every field is optional on its own; the
     * "all four or none" rule is checked in [validate], against what will be
     * stored once the change lands.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'bank_account_holder_name' => ['nullable', 'string', 'min:2', 'max:150', "regex:/^[\\pL .'\\-]+$/u"],
            'bank_name' => ['nullable', 'string', 'min:2', 'max:150', "regex:/^[\\pL0-9 .&'()\\-]+$/u"],
            // Indian account numbers are 9 to 18 digits.
            'bank_account_number' => ['nullable', 'string', 'regex:/^\\d{9,18}$/'],
            // 4 letters, a zero, then 6 letters or digits.
            'bank_ifsc' => ['nullable', 'string', 'regex:/^[A-Z]{4}0[A-Z0-9]{6}$/'],
            'bank_upi_id' => ['nullable', 'string', 'max:100', 'regex:/^[A-Za-z0-9.\\-_]{2,256}@[A-Za-z][A-Za-z0-9]{1,63}$/'],
        ];
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'bank_account_holder_name.regex' => 'The account holder name can only contain letters, spaces, dots, hyphens and apostrophes.',
            'bank_name.regex' => 'Enter a valid bank name.',
            'bank_account_number.regex' => 'The account number must be 9 to 18 digits.',
            'bank_ifsc.regex' => 'Enter a valid IFSC code, for example HDFC0001234.',
            'bank_upi_id.regex' => 'Enter a valid UPI ID, for example name@okhdfcbank.',
        ];
    }

    /**
     * Tidy what a person typed: spaces out of the account number, IFSC in
     * capitals, everything trimmed, blanks as null. Only the bank keys come
     * back, and only the ones that were sent.
     *
     * @param  array<string, mixed>  $input
     * @return array<string, ?string>
     */
    public function normalise(array $input): array
    {
        $out = [];

        foreach (self::FIELDS as $field) {
            if (! array_key_exists($field, $input)) {
                continue;
            }

            $value = $input[$field];
            $value = is_string($value) ? trim($value) : ($value === null ? null : trim((string) $value));

            if ($field === 'bank_account_number' && $value !== null) {
                $value = preg_replace('/[\s-]+/', '', $value);
            }

            if ($field === 'bank_ifsc' && $value !== null) {
                $value = strtoupper(preg_replace('/\s+/', '', $value));
            }

            if ($field === 'bank_upi_id' && $value !== null) {
                $value = preg_replace('/\s+/', '', $value);
            }

            $out[$field] = ($value === '' ? null : $value);
        }

        return $out;
    }

    /**
     * Validate a change against what is already stored and return the clean
     * values to write. An account number left blank keeps the saved one — the
     * forms only ever show it masked, so asking for it again just to change
     * the UPI ID would be pointless.
     *
     * @param  array<string, mixed>  $input
     * @return array<string, ?string>
     *
     * @throws ValidationException
     */
    public function validate(array $input, ?Model $current = null): array
    {
        $clean = $this->normalise($input);

        Validator::make($clean, $this->rules(), $this->messages())->validate();

        if ($current && empty($clean['bank_account_number']) && filled($current->bank_account_number)) {
            unset($clean['bank_account_number']);
        }

        // The four transfer fields come together or not at all: a number with
        // no IFSC cannot be paid into.
        $merged = [];
        foreach (self::REQUIRED as $field) {
            $merged[$field] = array_key_exists($field, $clean) ? $clean[$field] : $current?->{$field};
        }

        $given = array_filter($merged, fn ($v) => filled($v));
        if ($given !== [] && count($given) < count(self::REQUIRED)) {
            $missing = array_diff(self::REQUIRED, array_keys($given));
            $errors = [];
            foreach ($missing as $field) {
                $errors[$field] = 'Add the '.$this->label($field).' too, or leave all bank account fields empty.';
            }
            throw ValidationException::withMessages($errors);
        }

        return $clean;
    }

    /**
     * Write validated values onto a salon or an enquiry. Returns whether
     * anything changed.
     *
     * @param  array<string, ?string>  $clean  Output of [validate].
     */
    public function apply(Model $target, array $clean, ?User $actor = null): bool
    {
        foreach ($clean as $field => $value) {
            $target->{$field} = $value;
        }

        if (array_key_exists('bank_account_number', $clean)) {
            $target->bank_account_last4 = $clean['bank_account_number'] ? substr($clean['bank_account_number'], -4) : null;
        }

        if (! $target->isDirty()) {
            return false;
        }

        if ($target instanceof Salon) {
            $target->bank_details_updated_at = now();
            $target->bank_details_updated_by = $actor?->id;
        }

        $target->save();

        return true;
    }

    /** Copy an enquiry's details onto the salon it became, if the salon has none. */
    public function carryFromEnquiry(Model $enquiry, Salon $salon, ?User $actor = null): void
    {
        if ($this->hasAny($salon) || ! $this->hasAny($enquiry)) {
            return;
        }

        $values = [];
        foreach (self::FIELDS as $field) {
            $values[$field] = $enquiry->{$field};
        }

        $this->apply($salon, $values, $actor);
    }

    /**
     * The stored values, ready for [apply] onto another salon — for an owner
     * reusing one account across their branches.
     *
     * @return array<string, ?string>
     */
    public function valuesOf(Model $source): array
    {
        $values = [];
        foreach (self::FIELDS as $field) {
            $values[$field] = $source->{$field};
        }

        return $values;
    }

    /**
     * An owner's salons whose account could be copied to another branch, as
     * [present] shows them, with the salon's id and name.
     *
     * @return array<int, array<string, mixed>>
     */
    public function copyableFor(string $ownerId, ?string $exceptSalonId = null): array
    {
        return Salon::where('admin_id', $ownerId)
            ->when($exceptSalonId, fn ($q) => $q->where('id', '!=', $exceptSalonId))
            ->orderBy('name')
            ->get()
            ->filter(fn (Salon $salon) => $this->hasRequired($salon))
            ->map(fn (Salon $salon) => ['salon_id' => $salon->id, 'salon_name' => $salon->name] + $this->present($salon))
            ->values()
            ->all();
    }

    /** Whether everything a bank transfer needs is on file. */
    public function hasRequired(Model $target): bool
    {
        foreach (self::REQUIRED as $field) {
            if (blank($target->{$field})) {
                return false;
            }
        }

        return true;
    }

    public function hasAny(Model $target): bool
    {
        foreach (self::FIELDS as $field) {
            if (filled($target->{$field})) {
                return true;
            }
        }

        return false;
    }

    /**
     * What a client may see: everything but the full account number, which is
     * shown as its last four digits. [$revealAccount] is for the superadmin
     * paying a settlement, and is audited by the caller.
     *
     * @return array<string, mixed>
     */
    public function present(Model $target, bool $revealAccount = false): array
    {
        $last4 = $target->bank_account_last4
            ?: ($target->bank_account_number ? substr($target->bank_account_number, -4) : null);

        return [
            'account_holder_name' => $target->bank_account_holder_name,
            'bank_name' => $target->bank_name,
            'ifsc' => $target->bank_ifsc,
            'upi_id' => $target->bank_upi_id,
            'account_number_last4' => $last4,
            'account_number_masked' => $last4 ? str_repeat('•', 4).' '.$last4 : null,
            'account_number' => $revealAccount ? $target->bank_account_number : null,
            'has_required' => $this->hasRequired($target),
            'has_any' => $this->hasAny($target),
            'updated_at' => $target instanceof Salon ? $target->bank_details_updated_at?->toIso8601String() : null,
        ];
    }

    private function label(string $field): string
    {
        return match ($field) {
            'bank_account_holder_name' => 'account holder name',
            'bank_name' => 'bank name',
            'bank_account_number' => 'account number',
            'bank_ifsc' => 'IFSC code',
            default => str_replace('_', ' ', $field),
        };
    }
}
