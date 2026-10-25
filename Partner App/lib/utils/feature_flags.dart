/// Switches for features that exist in the app but are not offered right now.

/// "Start without scanning" on an appointment: begins it without the
/// customer's QR code. Built for testing; hidden for real salons so every
/// online booking is checked in by scanning. Flip to true to bring it back.
const bool kShowManualCheckIn = false;
