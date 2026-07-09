import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/order.dart';
import '../widgets/app_dropdown_styles.dart';

String _trOrLocaleFallback(
  AppLocalizations? l10n,
  String key, {
  required String en,
  required String he,
  required String ar,
}) {
  final t = l10n?.tr(key);
  if (t != null && t != key) return t;
  switch (l10n?.locale.languageCode) {
    case 'he':
      return he;
    case 'ar':
      return ar;
    default:
      return en;
  }
}

/// Single palette for order statuses — one distinct hue per [OrderStatus] so
/// table pills, filter dots, and dropdowns stay visually aligned.
Color orderStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.active:
      return const Color(0xFF0F7B6C);
    case OrderStatus.preparing:
      return const Color(0xFF2563EB);
    case OrderStatus.sentToSupplier:
      return const Color(0xFF38BDF8);
    case OrderStatus.inAssembly:
      return const Color(0xFFE09700);
    case OrderStatus.awaitingShipping:
      return const Color(0xFF9065B0);
    case OrderStatus.handled:
      return AppTheme.secondary;
    case OrderStatus.delivered:
      return const Color(0xFF448361);
    case OrderStatus.canceled:
      return const Color(0xFFE03E3E);
  }
}

String orderStatusLocalizedLabel(OrderStatus status, AppLocalizations? l10n) {
  switch (status) {
    case OrderStatus.active:
      return _trOrLocaleFallback(
        l10n,
        'active',
        en: 'Active',
        he: 'פעילה',
        ar: 'نشط',
      );
    case OrderStatus.preparing:
      return _trOrLocaleFallback(
        l10n,
        'preparing',
        en: 'Preparing',
        he: 'בהכנה',
        ar: 'قيد التحضير',
      );
    case OrderStatus.sentToSupplier:
      return _trOrLocaleFallback(
        l10n,
        'sentToSupplier',
        en: 'Sent to supplier',
        he: 'נשלח לסוכן',
        ar: 'تم الإرسال للمورد',
      );
    case OrderStatus.inAssembly:
      return _trOrLocaleFallback(
        l10n,
        'inAssembly',
        en: 'In Assembly',
        he: 'בהרכבה',
        ar: 'قيد التركيب',
      );
    case OrderStatus.awaitingShipping:
      return _trOrLocaleFallback(
        l10n,
        'awaitingShipping',
        en: 'Ready for pickup',
        he: 'מוכן לאיסוף',
        ar: 'جاهز للاستلام',
      );
    case OrderStatus.handled:
      return _trOrLocaleFallback(
        l10n,
        'handled',
        en: 'Handled',
        he: 'טופל',
        ar: 'تمت المعالجة',
      );
    case OrderStatus.delivered:
      return _trOrLocaleFallback(
        l10n,
        'delivered',
        en: 'Delivered',
        he: 'נמסרה',
        ar: 'تم التسليم',
      );
    case OrderStatus.canceled:
      return _trOrLocaleFallback(
        l10n,
        'canceled',
        en: 'Canceled',
        he: 'מבוטלת',
        ar: 'ملغي',
      );
  }
}

/// Small filled circle (Notion-style). Always wrapped in a fixed box when used
/// in [DropdownMenu.leadingIcon] so the anchor field does not expand the dot.
Widget orderStatusDot(Color color, {double size = 9}) {
  return SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    ),
  );
}

Widget orderStatusFilterAllLeading() {
  return Icon(
    Icons.filter_alt_outlined,
    size: 16,
    color: AppTheme.onSurfaceVariant,
  );
}

Widget leadingIconForStatusFilterValue(String value) {
  if (value == 'All') {
    return dropdownLeadingSlot(orderStatusFilterAllLeading());
  }
  final s = OrderStatusExtension.fromString(value);
  return dropdownLeadingSlot(
    orderStatusDot(orderStatusColor(s), size: 9),
  );
}

Widget leadingIconForOrderStatus(OrderStatus s) {
  return dropdownLeadingSlot(
    orderStatusDot(orderStatusColor(s), size: 9),
  );
}

/// Menu row leading: dot left-aligned in a consistent column.
Widget dropdownMenuEntryStatusDot(OrderStatus s) {
  return SizedBox(
    width: 22,
    height: 22,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: orderStatusDot(orderStatusColor(s), size: 9),
    ),
  );
}
