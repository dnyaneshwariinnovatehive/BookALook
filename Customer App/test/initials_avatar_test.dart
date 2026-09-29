import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/widgets/initials_avatar.dart';

void main() {
  group('initialsOf', () {
    test('uses first and last letter for a two-word name', () {
      expect(InitialsAvatar.initialsOf('Aarav Sharma'), 'AS');
      expect(InitialsAvatar.initialsOf('Anita Verma'), 'AV');
    });

    test('two people sharing a surname are told apart', () {
      // The whole reason this is two letters and not one. Note that two people
      // sharing *both* names really would both be "AS" — the initial stands in
      // for the name, it is not a unique id.
      expect(
        InitialsAvatar.initialsOf('Aarav Sharma'),
        isNot(InitialsAvatar.initialsOf('Aarav Anand')),
      );
      expect(InitialsAvatar.initialsOf('Aarav Sharma'), 'AS');
      expect(InitialsAvatar.initialsOf('Aarav Anand'), 'AA');
    });

    test('skips a middle name', () {
      expect(InitialsAvatar.initialsOf('Aarav Kumar Sharma'), 'AS');
    });

    test('uses the single letter when there is only one word', () {
      expect(InitialsAvatar.initialsOf('Aarav'), 'A');
    });

    test('ignores punctuation, hyphens and stray spacing', () {
      expect(InitialsAvatar.initialsOf('Aarav  Sharma'), 'AS');
      expect(InitialsAvatar.initialsOf('Aarav Sharma-Jain'), 'AJ');
      expect(InitialsAvatar.initialsOf('  Aarav Sharma  '), 'AS');
      expect(InitialsAvatar.initialsOf('Aarav, Sharma'), 'AS');
    });

    test('ignores a title so it is not read as a name', () {
      expect(InitialsAvatar.initialsOf('Dr. Priya Sharma'), 'PS');
      expect(InitialsAvatar.initialsOf('Mrs. Anita Verma'), 'AV');
      expect(InitialsAvatar.initialsOf('Prof Aarav Kumar Sharma'), 'AS');
    });

    test('ignores a parenthetical qualification', () {
      expect(InitialsAvatar.initialsOf('Dr. Aarav Sharma (Jr)'), 'AS');
    });

    test('falls back to ? only when there is no letter at all', () {
      expect(InitialsAvatar.initialsOf(''), '?');
      expect(InitialsAvatar.initialsOf('   '), '?');
      expect(InitialsAvatar.initialsOf('12345'), '?');
      expect(InitialsAvatar.initialsOf('(Jr)'), '?');
    });

    test('a title-only name still yields a letter', () {
      expect(InitialsAvatar.initialsOf('Dr.'), 'D');
    });
  });

  group('widget', () {
    Widget harness(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('renders the initials as its child', (tester) async {
      await tester.pumpWidget(
        harness(const InitialsAvatar(name: 'Aarav Sharma')),
      );

      expect(find.text('AS'), findsOneWidget);
    });

    testWidgets('renders the fallback for an empty name', (tester) async {
      await tester.pumpWidget(harness(const InitialsAvatar(name: '')));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('honours the requested radius', (tester) async {
      await tester.pumpWidget(
        harness(const InitialsAvatar(name: 'Aarav Sharma', radius: 30)),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 30);
    });
  });
}
