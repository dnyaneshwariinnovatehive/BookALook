import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/service_models.dart';
import 'package:partner_app/screens/dashboard/services/add_service_flow.dart';
import 'package:partner_app/theme/app_theme.dart';

void main() {
  final sampleCategoryHair = ServiceCategory(
    id: 'cat-hair-1',
    name: 'Hair Care',
    templates: [
      ServiceTemplate(
        id: 't-hair-1',
        categoryId: 'cat-hair-1',
        name: "Men's Haircut",
        estimatedDurationMinutes: 30,
      ),
      ServiceTemplate(
        id: 't-hair-2',
        categoryId: 'cat-hair-1',
        name: 'Beard Trim',
        estimatedDurationMinutes: 20,
      ),
    ],
  );

  final sampleCategorySpa = ServiceCategory(
    id: 'cat-spa-2',
    name: 'Spa & Massage',
    templates: [
      ServiceTemplate(
        id: 't-spa-1',
        categoryId: 'cat-spa-2',
        name: 'Aromatherapy Massage',
        estimatedDurationMinutes: 60,
      ),
    ],
  );

  Widget createWidget({
    required List<ServiceCategory> categories,
    required List<SalonService> existingServices,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 1500)),
        child: AddServiceFlow(
          salonId: 'test-salon-123',
          initialCategories: categories,
          initialSalonServices: existingServices,
        ),
      ),
    );
  }

  group('AddServiceFlow - Duplicate Service Prevention', () {
    testWidgets('excludes already added service from template dropdown list', (tester) async {
      // Existing service: Men's Haircut (t-hair-1)
      final existingServices = [
        SalonService(
          id: 'serv-1',
          salonId: 'test-salon-123',
          templateId: 't-hair-1',
          price: 350,
          template: sampleCategoryHair.templates![0],
        ),
      ];

      await tester.pumpWidget(createWidget(
        categories: [sampleCategoryHair, sampleCategorySpa],
        existingServices: existingServices,
      ));
      await tester.pumpAndSettle();

      // Hair Care category should be selected.
      // Beard Trim (t-hair-2) should be selected as it is the only available template.
      expect(find.text('Beard Trim'), findsOneWidget);

      // Open the Template dropdown
      await tester.tap(find.text('Beard Trim'));
      await tester.pumpAndSettle();

      // "Men's Haircut" must NOT be in the dropdown items
      expect(find.text("Men's Haircut"), findsNothing);

      // "Beard Trim" and "➕ Create Custom Service" should be present
      expect(find.text('Beard Trim'), findsWidgets);
      expect(find.text('➕ Create Custom Service'), findsOneWidget);
    });

    testWidgets('defaults to custom service when all templates in a category are already added', (tester) async {
      // Both templates in Hair Care are already added
      final existingServices = [
        SalonService(
          id: 'serv-1',
          salonId: 'test-salon-123',
          templateId: 't-hair-1',
          price: 350,
          template: sampleCategoryHair.templates![0],
        ),
        SalonService(
          id: 'serv-2',
          salonId: 'test-salon-123',
          templateId: 't-hair-2',
          price: 200,
          template: sampleCategoryHair.templates![1],
        ),
      ];

      // Spa category has available template, so it picks Spa or if Hair is selected it shows custom
      await tester.pumpWidget(createWidget(
        categories: [sampleCategoryHair],
        existingServices: existingServices,
      ));
      await tester.pumpAndSettle();

      // Custom service input field 'Name' should be visible because no templates are left
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('➕ Create Custom Service'), findsOneWidget);
    });
  });

  group('AddServiceFlow - Refund Advance Checkbox Logic', () {
    testWidgets('checkbox is enabled when advance percentage > 0% and disabled when 0%', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidget(
        categories: [sampleCategoryHair],
        existingServices: [],
      ));
      await tester.pumpAndSettle();

      // Default advance is 20%
      expect(find.text('20'), findsOneWidget);

      // Checkbox should be enabled (onChanged is not null)
      var checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNotNull);
      expect(checkbox.value, isFalse);

      // Tap checkbox to check it
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);

      // Now change advance percentage to 0
      final numericFields = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.number,
      );
      final advanceField = numericFields.last;
      await tester.enterText(advanceField, '0');
      await tester.pumpAndSettle();

      // Checkbox must now be automatically unchecked and disabled (onChanged is null)
      checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
      expect(checkbox.onChanged, isNull);

      // Attempting to tap the checkbox should do nothing
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
      expect(checkbox.onChanged, isNull);

      // Now change advance percentage to 15%
      await tester.enterText(advanceField, '15');
      await tester.pumpAndSettle();

      // Checkbox must be enabled again
      checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNotNull);

      // Tap to check it again
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('rejects custom service with name matching existing service (case & whitespace insensitive)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final existingServices = [
        SalonService(
          id: 'serv-1',
          salonId: 'test-salon-123',
          templateId: 't-hair-1',
          price: 350,
          template: sampleCategoryHair.templates![0], // Men's Haircut
        ),
      ];

      await tester.pumpWidget(createWidget(
        categories: [sampleCategoryHair],
        existingServices: existingServices,
      ));
      await tester.pumpAndSettle();

      // Switch to custom service mode
      await tester.tap(find.text('Beard Trim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('➕ Create Custom Service').last);
      await tester.pumpAndSettle();

      // Enter "  men's haircut  " in the Name field
      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, "  men's haircut  ");
      await tester.pumpAndSettle();

      // Enter price
      final priceField = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.number,
      ).first;
      await tester.enterText(priceField, '400');
      await tester.pumpAndSettle();

      // Tap Add Service button to trigger validation
      final addButton = find.widgetWithText(ElevatedButton, 'Add Service');
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Validation error must be shown
      expect(find.text('This service already exists in this salon'), findsOneWidget);
    });
  });
}

