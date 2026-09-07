import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/editorial_screen_title.dart';
import '../orders/quotes_list_tab.dart';

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

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceContainerLowest,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 0,
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
