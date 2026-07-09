import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../config/app_theme.dart';
import 'brand_logo.dart';
import '../screens/dashboard_screen.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/payments/payments_screen.dart';
import '../screens/assemblies/assemblies_screen.dart';
import '../screens/suppliers/suppliers_screen.dart';
import '../screens/fixing/fixing_screen.dart';
import '../screens/inventory/inventory_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int? _prevIndex;
  bool _sidebarCollapsed = false;

  /// Sidebar labels: for Hebrew/Arabic, always use the explicit [he]/[ar] strings.
  /// Otherwise a stale cached `app_*.arb` asset (common on Flutter web) can still
  /// return old translations from [AppLocalizations.tr] and override the UI.
  String _l10nOrLocale(
    BuildContext context,
    AppLocalizations? l10n,
    String key, {
    required String en,
    required String he,
    required String ar,
  }) {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'he') return he;
    if (lang == 'ar') return ar;
    final t = l10n?.tr(key) ?? '';
    if (t.isNotEmpty && t != key) return t;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedNavIndexProvider);
    final locale = ref.watch(localeProvider);
    final l10n = AppLocalizations.of(context);
    final prev = _prevIndex ?? selectedIndex;
    final movingForward = selectedIndex >= prev;
    _prevIndex = selectedIndex;

    final screens = [
      const DashboardScreen(),
      const CustomersScreen(),
      const OrdersScreen(),
      const FixingScreen(),
      const PaymentsScreen(),
      const AssembliesScreen(),
      const SuppliersScreen(),
      const InventoryScreen(),
    ];
    // Keys so AnimatedSwitcher can animate between screens
    final screenKeys = List.generate(screens.length, (i) => ValueKey<int>(i));

    final navItems = [
      _NavItem(
        Icons.dashboard_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'dashboard',
          en: 'Dashboard',
          he: 'לוח בקרה',
          ar: 'لوحة التحكم',
        ),
      ),
      _NavItem(
        Icons.people_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'customers',
          en: 'Customers',
          he: 'לקוחות',
          ar: 'العملاء',
        ),
      ),
      _NavItem(
        Icons.shopping_cart_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'orders',
          en: 'Orders',
          he: 'הזמנות',
          ar: 'الطلبات',
        ),
      ),
      _NavItem(
        Icons.build_circle_outlined,
        _l10nOrLocale(
          context,
          l10n,
          'fixing',
          en: 'Fixing',
          he: 'תיקון',
          ar: 'إصلاح',
        ),
      ),
      _NavItem(
        Icons.payment_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'payments',
          en: 'Payments',
          he: 'תשלומים',
          ar: 'المدفوعات',
        ),
      ),
      _NavItem(
        Icons.build_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'assemblies',
          en: 'Assemblies',
          he: 'הרכבות',
          ar: 'التركيبات',
        ),
      ),
      _NavItem(
        Icons.local_shipping_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'suppliers',
          en: 'Suppliers',
          he: 'סוכנים',
          ar: 'الموردون',
        ),
      ),
      _NavItem(
        Icons.inventory_2_rounded,
        _l10nOrLocale(
          context,
          l10n,
          'inventory',
          en: 'Inventory',
          he: 'מלאי',
          ar: 'المخزون',
        ),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            width: _sidebarCollapsed ? 76 : 220,
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Logo / Brand + collapse toggle
                SizedBox(
                  height: 90,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: AppTheme.surfaceCard),
                      ),
                      PositionedDirectional(
                        top: 10,
                        start: _sidebarCollapsed ? 8 : null,
                        end: _sidebarCollapsed ? null : 10,
                        child: Material(
                          color: Colors.transparent,
                          child: IconButton(
                            tooltip: _sidebarCollapsed
                                ? (l10n?.tr('expand') ?? 'Expand')
                                : (l10n?.tr('collapse') ?? 'Collapse'),
                            onPressed: () => setState(
                              () => _sidebarCollapsed = !_sidebarCollapsed,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.surfaceLight,
                              foregroundColor: AppTheme.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Icon(
                                _sidebarCollapsed
                                    ? Icons.chevron_right_rounded
                                    : Icons.chevron_left_rounded,
                                key: ValueKey(_sidebarCollapsed),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!_sidebarCollapsed)
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: -10,
                          child: Center(
                            child: BrandLogo(
                              width: 100,
                              height: 100,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Navigation items
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: _sidebarCollapsed ? 6 : 8,
                      vertical: 0,
                    ),
                    itemCount: navItems.length,
                    itemBuilder: (context, index) {
                      final isSelected = selectedIndex == index;
                      final iconColor = isSelected
                          ? AppTheme.primaryGold
                          : AppTheme.textSecondary;
                      final labelStyle = TextStyle(
                        color: iconColor,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 15,
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              ref
                                  .read(selectedNavIndexProvider.notifier)
                                  .setIndex(index);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: EdgeInsets.symmetric(
                                horizontal: _sidebarCollapsed ? 10 : 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? AppTheme.primaryGold.withValues(
                                        alpha: 0.15,
                                      )
                                    : Colors.transparent,
                                border: isSelected
                                    ? Border.all(
                                        color: AppTheme.primaryGold.withValues(
                                          alpha: 0.3,
                                        ),
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: _sidebarCollapsed
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  Icon(
                                    navItems[index].icon,
                                    color: iconColor,
                                    size: 24,
                                  ),
                                  if (!_sidebarCollapsed) ...[
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        child: Text(
                                          navItems[index].label,
                                          key: ValueKey(
                                            'nav_label_${index}_${navItems[index].label}',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          style: labelStyle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Language switcher
                AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubic,
                  padding: EdgeInsets.all(_sidebarCollapsed ? 8 : 12),
                  child: _sidebarCollapsed
                      ? Column(
                          children: [
                            _languageChip('עב', 'he', locale, ref),
                            const SizedBox(height: 8),
                            _languageChip('عر', 'ar', locale, ref),
                            const SizedBox(height: 8),
                            _languageChip('EN', 'en', locale, ref),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _languageChip('עב', 'he', locale, ref),
                            _languageChip('عر', 'ar', locale, ref),
                            _languageChip('EN', 'en', locale, ref),
                          ],
                        ),
                ),
                // Logout
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    _sidebarCollapsed ? 8 : 12,
                    0,
                    _sidebarCollapsed ? 8 : 12,
                    16,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: _sidebarCollapsed
                        ? OutlinedButton(
                            onPressed: () async {
                              final authService = ref.read(authServiceProvider);
                              await authService.signOut();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.error,
                              side: const BorderSide(color: AppTheme.error),
                              minimumSize: const Size(0, 48),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.logout_rounded, size: 20),
                          )
                        : OutlinedButton.icon(
                            onPressed: () async {
                              final authService = ref.read(authServiceProvider);
                              await authService.signOut();
                            },
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            label: Text(l10n?.tr('logout') ?? 'Logout'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.error,
                              side: const BorderSide(color: AppTheme.error),
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Main content with heavier cross-fade + subtle scale
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInQuart,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: Offset(movingForward ? 0.04 : -0.04, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic),
                );
                final scale = Tween<double>(begin: 0.98, end: 1.0).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutQuart),
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: slide,
                    child: ScaleTransition(
                      scale: scale,
                      alignment: Alignment.center,
                      child: child,
                    ),
                  ),
                );
              },
              child: KeyedSubtree(
                key: screenKeys[selectedIndex],
                child: screens[selectedIndex],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _languageChip(
  String label,
  String code,
  Locale currentLocale,
  WidgetRef ref,
) {
  final isSelected = currentLocale.languageCode == code;
  return GestureDetector(
    onTap: () {
      ref.read(localeProvider.notifier).setLocale(Locale(code));
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isSelected
            ? AppTheme.primaryGold.withValues(alpha: 0.2)
            : AppTheme.surfaceLight,
        border: isSelected
            ? Border.all(color: AppTheme.primaryGold, width: 1.5)
            : Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryGold : AppTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem(this.icon, this.label);
}
