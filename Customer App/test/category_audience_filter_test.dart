import 'package:customer_app/screens/category_salons_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The category screen starts filtered to the customer's own audience. A salon
/// row without `gender_focus` used to fail that filter, so every category said
/// "No salons found" to anyone with a gender on their profile.
void main() {
  test('a salon that does not say whom it serves is shown to everyone', () {
    final row = <String, dynamic>{'id': 's1', 'name': 'Glow Up Studio'};
    expect(salonServesAudience(row, 'Women Only'), isTrue);
    expect(salonServesAudience(row, 'Men Only'), isTrue);
    expect(salonServesAudience(row, 'All'), isTrue);
  });

  test('single-gender salons are kept from the other audience', () {
    final women = <String, dynamic>{'gender_focus': 'Women Only'};
    final men = <String, dynamic>{'gender_focus': 'Men Only'};
    final unisex = <String, dynamic>{'gender_focus': 'Unisex'};

    expect(salonServesAudience(women, 'Women Only'), isTrue);
    expect(salonServesAudience(women, 'Men Only'), isFalse);
    expect(salonServesAudience(men, 'Women Only'), isFalse);
    expect(salonServesAudience(unisex, 'Men Only'), isTrue);
    expect(salonServesAudience(unisex, 'Unisex'), isTrue);
    expect(salonServesAudience(women, 'Unisex'), isFalse);
  });
}
