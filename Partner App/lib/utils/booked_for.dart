/// Who is actually coming in, when a customer booked for someone else.
///
/// The booking still belongs to the account holder, who paid and is the one
/// to call. This is the person who sits in the chair: "For Rohan (Male)".
/// Null for a booking the customer made for themselves, and for every booking
/// made before the app could say otherwise.
String? bookedForLabel(Map<String, dynamic>? appointment) {
  if (appointment == null || appointment['booked_for'] != 'other') return null;

  final name = (appointment['recipient_name'] ?? '').toString().trim();
  if (name.isEmpty) return null;

  final gender = switch ((appointment['recipient_gender'] ?? '').toString()) {
    'male' => 'Male',
    'female' => 'Female',
    'other' => 'Other',
    _ => null,
  };

  return gender == null ? 'For $name' : 'For $name ($gender)';
}
