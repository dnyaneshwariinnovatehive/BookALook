import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/collaborator/service_picker_sheet.dart';
import 'package:partner_app/theme/app_theme.dart';

void main() {
  final sampleCatalog = [
    {
      'id': 'cat-1',
      'name': 'Hair Styling',
      'templates': [
        {
          'id': 't-1',
          'name': 'Classic Haircut',
          'estimated_duration_minutes': 30,
        },
        {
          'id': 't-2',
          'name': 'Beard Grooming',
          'estimated_duration_minutes': 20,
        },
      ],
    },
    {
      'id': 'cat-2',
      'name': 'Facials',
      'templates': [
        {
          'id': 't-3',
          'name': 'Gold Facial',
          'estimated_duration_minutes': 45,
        },
      ],
    },
  ];

  Widget buildSheet({
    Set<String> existingTemplateIds = const {},
    Set<String> existingCustomIdentities = const {},
    List<dynamic>? categories,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ServicePickerSheet(
          initialCategories: categories ?? sampleCatalog,
          existingTemplateIds: existingTemplateIds,
          existingCustomIdentities: existingCustomIdentities,
        ),
      ),
    );
  }

  testWidgets('an already-added standard service cannot be selected again and is marked Added', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSheet(
        existingTemplateIds: {'t-1'},
      ),
    );
    await tester.pumpAndSettle();

    // Classic Haircut must display an "Added" badge
    expect(find.text('Classic Haircut'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);

    // Tapping Classic Haircut should show SnackBar and NOT proceed to price step
    await tester.tap(find.text('Classic Haircut'));
    await tester.pump();
    expect(find.text('This service is already in the draft.'), findsOneWidget);
    expect(find.text('Add to the menu'), findsNothing);

    // Tapping Beard Grooming (which is not added) proceeds to price step
    await tester.tap(find.text('Beard Grooming'));
    await tester.pumpAndSettle();

    expect(find.text('Add to the menu'), findsOneWidget);
    expect(find.text('Price (₹) *'), findsOneWidget);
  });

  testWidgets('a duplicate custom service is rejected', (tester) async {
    final existingCustomIdentity = ServicePickerSheet.normalizeCustomIdentity('Other', 'Custom Facial');

    await tester.pumpWidget(
      buildSheet(
        existingCustomIdentities: {existingCustomIdentity},
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Custom view
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    // Fill in identical name and category
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Beard sculpt'), '  custom facial  ');
    await tester.enterText(find.widgetWithText(TextField, '0'), '450');

    // Submit
    await tester.tap(find.text('Add to the menu'));
    await tester.pump();

    // Verify duplicate error snackbar is displayed
    expect(find.text('This custom service has already been added in "Other".'), findsOneWidget);
  });

  testWidgets('legitimate distinct services remain selectable', (tester) async {
    final existingCustomIdentity = ServicePickerSheet.normalizeCustomIdentity('Spa', 'Relaxation Oil');

    await tester.pumpWidget(
      buildSheet(
        existingCustomIdentities: {existingCustomIdentity},
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Custom view
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    // Enter distinct service name in Spa category
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Beard sculpt'), 'Deep Tissue Massage');
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Grooming — leave blank for "Other"'), 'Spa');
    await tester.enterText(find.widgetWithText(TextField, '0'), '800');

    await tester.tap(find.text('Add to the menu'));
    await tester.pump();

    // Verify NO duplicate error snackbar was shown
    expect(find.text('This custom service has already been added in "Spa".'), findsNothing);
  });

  test('existing selections remain correct and deduplicated after draft restoration', () {
    final draft = OnboardingDraft(enquiryId: 'test-enquiry-123');

    // Historical server payload with duplicate records
    final serverSalon = {
      'salon_name': 'Grand Luxury Salon',
      'services': [
        // Duplicate standard template t-1
        {
          'template_id': 't-1',
          'name': 'Classic Haircut',
          'category_name': 'Hair Styling',
          'duration_minutes': 30,
          'price': 250.0,
        },
        {
          'template_id': 't-1',
          'name': 'Classic Haircut',
          'category_name': 'Hair Styling',
          'duration_minutes': 30,
          'price': 260.0,
        },
        // Unique standard template t-2
        {
          'template_id': 't-2',
          'name': 'Beard Grooming',
          'category_name': 'Hair Styling',
          'duration_minutes': 20,
          'price': 150.0,
        },
        // Duplicate custom service in Grooming
        {
          'template_id': null,
          'name': 'Royal Shave',
          'category_name': 'Grooming',
          'duration_minutes': 30,
          'price': 300.0,
        },
        {
          'template_id': null,
          'name': '  royal shave  ',
          'category_name': 'Grooming',
          'duration_minutes': 30,
          'price': 350.0,
        },
        // Legitimate distinct custom service in a different category (Facials)
        {
          'template_id': null,
          'name': 'Royal Shave',
          'category_name': 'Facials',
          'duration_minutes': 30,
          'price': 400.0,
        },
      ],
    };

    draft.restoreFrom(serverSalon);

    // Verify exactly 4 deduplicated services exist: t-1, t-2, Grooming::Royal Shave, Facials::Royal Shave
    expect(draft.services.length, 4);

    final standardIds = draft.services.where((s) => s.templateId != null).map((s) => s.templateId).toList();
    expect(standardIds, ['t-1', 't-2']);

    final customIdentities = draft.services
        .where((s) => s.templateId == null)
        .map((s) => '${s.categoryName.trim().toLowerCase()}::${s.name.trim().toLowerCase()}')
        .toList();
    expect(customIdentities, ['grooming::royal shave', 'facials::royal shave']);
  });

  testWidgets('services are listed organized by category with Category Dropdown filter', (
    tester,
  ) async {
    await tester.pumpWidget(buildSheet());
    await tester.pumpAndSettle();

    // Verify both category expansion headers are visible
    expect(find.text('Hair Styling'), findsOneWidget);
    expect(find.text('Facials'), findsOneWidget);

    // Verify services are displayed under their categories
    expect(find.text('Classic Haircut'), findsOneWidget);
    expect(find.text('Beard Grooming'), findsOneWidget);
    expect(find.text('Gold Facial'), findsOneWidget);

    // Verify Category Dropdown is present
    expect(find.byType(DropdownButton<String?>), findsOneWidget);

    // Tap dropdown to open category selector
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();

    // Select "Facials (1)"
    await tester.tap(find.text('Facials (1)').last);
    await tester.pumpAndSettle();

    // Now only Facials should be displayed; Hair Styling should be filtered out
    expect(find.text('Gold Facial'), findsOneWidget);
    expect(find.text('Classic Haircut'), findsNothing);
    expect(find.text('Beard Grooming'), findsNothing);

    // Switch back to "All Categories (3 services)"
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Categories (3 services)').last);
    await tester.pumpAndSettle();

    // All services should be visible again
    expect(find.text('Classic Haircut'), findsOneWidget);
    expect(find.text('Beard Grooming'), findsOneWidget);
    expect(find.text('Gold Facial'), findsOneWidget);
  });
}

