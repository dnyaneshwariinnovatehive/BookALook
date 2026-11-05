import 'package:customer_app/utils/time_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('policy windows read naturally', () {
    expect(formatMinutes(45), '45 minutes');
    expect(formatMinutes(1), '1 minute');
    expect(formatMinutes(60), '1 hour');
    expect(formatMinutes(90), '1 hour 30 minutes');
    expect(formatMinutes(120), '2 hours');
    expect(formatMinutes(300), '5 hours');
    expect(formatMinutes(1500), '1 day 1 hour');
    expect(formatMinutes(0), '0 minutes');
  });
}
