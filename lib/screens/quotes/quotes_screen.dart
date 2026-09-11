import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import '../../widgets/editorial_screen_title.dart';
import '../orders/quotes_list_tab.dart';
import 'quote_form_screen.dart';

/// Top-level Quotes page — same list/actions as the former Orders sub-tab.
class QuotesScreen extends ConsumerWidget {
  const QuotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title = () {
      final t = l10n?.tr('quotes');
      if (t != null && t.isNotEmpty && t != 'quotes') return t;
      return switch (Localizations.localeOf(context).languageCode) {
        'he' => 'הצעות מחיר',
        'ar' => 'عروض الأسعار',
        _ => 'Quotes',
      };
    }();

    final newQuoteLabel = () {
      final t = l10n?.tr('newQuote');
      if (t != null && t.isNotEmpty && t != 'newQuote') return t;
      return switch (Localizations.localeOf(context).languageCode) {
        'he' => 'הצעת מחיר חדשה',
        'ar' => 'عرض سعر جديد',
        _ => 'New quote',
      };
    }();

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceContainerLowest,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 0,
      ),
      floatingActionButton: Padding(
        // Clears the list's pagination bar, matching the Orders screen.
        padding: const EdgeInsets.only(bottom: 64),
        child: FloatingActionButton(
          backgroundColor: AppTheme.secondary,
          foregroundColor: AppTheme.onPrimary,
          elevation: 2,
          tooltip: newQuoteLabel,
          onPressed: () async {
            // No customer in context here — the form shows a picker.
            final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const QuoteFormScreen()),
            );
            if (created == true) {
              ref.invalidate(quotesProvider);
            }
          },
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorialScreenTitle(
            title: title,
            padding: const EdgeInsets.only(
              left: 32,
              right: 32,
              top: 20,
              bottom: 12,
            ),
          ),
          const Expanded(
            child: QuotesListTab(active: true),
          ),
        ],
      ),
    );
  }
}
