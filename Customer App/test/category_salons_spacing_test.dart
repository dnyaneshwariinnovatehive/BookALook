import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:customer_app/models/category.dart';
import 'package:customer_app/screens/category_salons_screen.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  Widget buildTestWidget({required Size screenSize}) {
    return MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: MaterialApp(
        home: CategorySalonsScreen(
          category: ServiceCategory(id: 'combo', name: 'Combos & Packages'),
        ),
      ),
    );
  }

  group('CategorySalonsScreen Horizontal Spacing & Responsiveness', () {
    testWidgets('renders properly on narrow phone (320px) without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      await tester.pumpWidget(buildTestWidget(screenSize: const Size(320, 700)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders properly on standard phone (390px) without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(buildTestWidget(screenSize: const Size(390, 844)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders properly on wide phone (430px) without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      await tester.pumpWidget(buildTestWidget(screenSize: const Size(430, 932)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  });
}
