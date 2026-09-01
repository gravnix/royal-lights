import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:royal_lights_app/l10n/app_localizations.dart';
import 'package:royal_lights_app/models/customer.dart';
import 'package:royal_lights_app/models/order.dart';
import 'package:royal_lights_app/models/payment.dart';
import 'package:royal_lights_app/models/quote.dart';
import 'package:royal_lights_app/models/timeline_note.dart';
import 'package:royal_lights_app/providers/providers.dart';
import 'package:royal_lights_app/screens/dashboard_screen.dart';

/// The dashboard packs several multi-column rows into one scroll view, so the
/// failure mode that matters is a horizontal overflow at a narrower window.
/// These cases render it at the three breakpoints in both text directions and
/// fail if Flutter reports any layout exception.
void main() {
  final now = DateTime.now();

  DateTime monthsAgo(int n) => DateTime(now.year, now.month - n, 15);

  final customers = [
    for (var i = 0; i < 8; i++)
      Customer(
        id: 'c$i',
        cardName: 'לקוח מספר $i',
        customerName: 'Customer $i',
        remainingDebt: i * 2400,
        createdAt: monthsAgo(i),
      ),
  ];

  final orders = [
    for (var i = 0; i < 20; i++)
      Order(
        id: 'o$i',
        customerId: 'c${i % 8}',
        status: OrderStatusExtension.all[i % OrderStatusExtension.all.length],
        totalPrice: 1000.0 * (i + 1),
        createdAt: monthsAgo(i % 12),
      ),
  ];

  final quotes = [
    for (var i = 0; i < 6; i++)
      Quote(
        id: 'q$i',
        customerId: 'c${i % 8}',
        status: i.isEven ? QuoteStatus.converted : QuoteStatus.sent,
        totalPrice: 500.0 * i,
        createdAt: monthsAgo(i % 3),
      ),
  ];

  final payments = [
    for (var i = 0; i < 5; i++)
      Payment(
        id: 'p$i',
        customerId: 'c$i',
        date: now.subtract(Duration(days: i * 15)),
        cardName: 'לקוח מספר $i',
        customerName: 'Customer $i',
        amount: 500,
      ),
  ];

  final notes = [
    TimelineNote(
      id: 'n1',
      noteDate: now,
      title: 'להתקשר לספק',
      body: 'לבדוק מלאי נברשות',
    ),
    TimelineNote(id: 'n2', noteDate: now.add(const Duration(days: 1)), title: 'משלוח'),
    TimelineNote(id: 'n3', noteDate: now.add(const Duration(days: 9)), title: 'הרכבה'),
  ];

  Widget harness(Locale locale) {
    return ProviderScope(
      overrides: [
        currentUsernameProvider.overrideWithValue('tester'),
        ordersProvider.overrideWith((ref) async => orders),
        customersProvider.overrideWith((ref) async => customers),
        quotesProvider.overrideWith((ref) async => quotes),
        paymentsProvider(null).overrideWith((ref) async => payments),
        timelineNotesProvider.overrideWith((ref) async => notes),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('he'), Locale('ar'), Locale('en')],
        home: Directionality(
          textDirection:
              locale.languageCode == 'en' ? TextDirection.ltr : TextDirection.rtl,
          child: const DashboardScreen(),
        ),
      ),
    );
  }

  setUpAll(() async {
    await initializeDateFormatting();
  });

  /// MaterialApp withholds `home` until the async localization delegates have
  /// loaded, and `pump()` cannot drive the real I/O that `rootBundle` does — so
  /// the first pump has to happen inside `runAsync`, otherwise every assertion
  /// below would run against an empty tree.
  Future<void> pumpDashboard(WidgetTester tester, Locale locale) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(locale));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    // Let the entry animation finish.
    await tester.pump(const Duration(seconds: 1));
  }

  void setSize(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final width in <double>[1440, 1000, 700]) {
    for (final locale in const [Locale('he'), Locale('en')]) {
      testWidgets(
        'renders without overflow at ${width.toInt()}px (${locale.languageCode})',
        (tester) async {
          setSize(tester, width);
          await pumpDashboard(tester, locale);

          // Proves the assertion below is running against a real tree.
          expect(find.text('tester'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('period toggle switches between monthly and yearly',
      (tester) async {
    setSize(tester, 1440);
    await pumpDashboard(tester, const Locale('he'));

    expect(find.text('החודש'), findsWidgets);

    await tester.tap(find.text('שנתי'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('השנה'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
