/**
 * Bank details rules, the same ones the backend applies (BankDetailsService),
 * so a typo is caught before the request is sent. The server still checks
 * everything; this only saves a round trip.
 */

export interface BankDetailsInput {
  bank_account_holder_name: string;
  bank_name: string;
  bank_account_number: string;
  bank_ifsc: string;
  bank_upi_id: string;
}

export const EMPTY_BANK_DETAILS: BankDetailsInput = {
  bank_account_holder_name: '',
  bank_name: '',
  bank_account_number: '',
  bank_ifsc: '',
  bank_upi_id: '',
};

export const BANK_FIELD_LABELS: Record<keyof BankDetailsInput, string> = {
  bank_account_holder_name: 'Account holder name',
  bank_name: 'Bank name',
  bank_account_number: 'Account number',
  bank_ifsc: 'IFSC code',
  bank_upi_id: 'UPI ID (optional)',
};

const HOLDER = /^[\p{L} .'\-]+$/u;
const BANK = /^[\p{L}0-9 .&'()\-]+$/u;
const ACCOUNT = /^\d{9,18}$/;
const IFSC = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const UPI = /^[A-Za-z0-9.\-_]{2,256}@[A-Za-z][A-Za-z0-9]{1,63}$/;

/** Trimmed, account number without spaces, IFSC in capitals. */
export function normaliseBankDetails(input: BankDetailsInput): BankDetailsInput {
  return {
    bank_account_holder_name: input.bank_account_holder_name.trim(),
    bank_name: input.bank_name.trim(),
    bank_account_number: input.bank_account_number.replace(/[\s-]/g, ''),
    bank_ifsc: input.bank_ifsc.replace(/\s/g, '').toUpperCase(),
    bank_upi_id: input.bank_upi_id.replace(/\s/g, ''),
  };
}

/**
 * Field errors, keyed like the API's. Empty means valid. [hasSavedAccount]
 * lets a blank account number stand for "keep the saved one".
 */
export function validateBankDetails(
  raw: BankDetailsInput,
  { hasSavedAccount = false }: { hasSavedAccount?: boolean } = {},
): Partial<Record<keyof BankDetailsInput, string>> {
  const v = normaliseBankDetails(raw);
  const errors: Partial<Record<keyof BankDetailsInput, string>> = {};

  if (v.bank_account_holder_name && (v.bank_account_holder_name.length < 2 || v.bank_account_holder_name.length > 150 || !HOLDER.test(v.bank_account_holder_name))) {
    errors.bank_account_holder_name = 'Only letters, spaces, dots, hyphens and apostrophes.';
  }
  if (v.bank_name && (v.bank_name.length < 2 || v.bank_name.length > 150 || !BANK.test(v.bank_name))) {
    errors.bank_name = 'Enter a valid bank name.';
  }
  if (v.bank_account_number && !ACCOUNT.test(v.bank_account_number)) {
    errors.bank_account_number = 'The account number must be 9 to 18 digits.';
  }
  if (v.bank_ifsc && !IFSC.test(v.bank_ifsc)) {
    errors.bank_ifsc = 'Enter a valid IFSC code, e.g. HDFC0001234.';
  }
  if (v.bank_upi_id && (v.bank_upi_id.length > 100 || !UPI.test(v.bank_upi_id))) {
    errors.bank_upi_id = 'Enter a valid UPI ID, e.g. name@okhdfcbank.';
  }

  // The four transfer fields come together or not at all.
  const core = {
    bank_account_holder_name: v.bank_account_holder_name,
    bank_name: v.bank_name,
    bank_account_number: v.bank_account_number || (hasSavedAccount ? 'saved' : ''),
    bank_ifsc: v.bank_ifsc,
  };
  const given = Object.values(core).filter(Boolean).length;
  if (given > 0 && given < 4) {
    (Object.keys(core) as (keyof typeof core)[]).forEach((k) => {
      if (!core[k] && !errors[k]) errors[k] = 'Fill this in too, or leave all bank account fields empty.';
    });
  }

  return errors;
}

/** Only the filled fields, cleaned — what to send. */
export function bankDetailsPayload(raw: BankDetailsInput): Partial<BankDetailsInput> {
  const v = normaliseBankDetails(raw);
  return Object.fromEntries(Object.entries(v).filter(([, value]) => value !== '')) as Partial<BankDetailsInput>;
}

export function isBankDetailsEmpty(raw: BankDetailsInput): boolean {
  return Object.values(raw).every((value) => value.trim() === '');
}
