# Royal Light Tira — Claude Onboarding

This file is auto-loaded into every Claude Code conversation in this repo. Read top-to-bottom on first contact, then jump by heading.

## 1. What this app is

Store-management Flutter app for **Royal Light Tira** — a lighting / home-goods retailer in Israel.

- Primary locale: **Hebrew (RTL)**. Arabic and English are supported.
- Targets: web (primary), macOS desktop, iOS. (Android folder absent.)
- Domain entities: customers → orders → order_items, payments, suppliers ("סוכנים"), inventory items, repair tickets ("fixing"), assembly jobs.

## 2. Tech stack

| Concern | Choice |
|---|---|
| UI | Flutter, Material 3, `google_fonts` (Assistant) |
| State | `flutter_riverpod` ^3.2.1 |
| Backend | `supabase_flutter` ^2.12.0 (Postgres + Auth + Storage + Edge Functions) |
| Routing | None — `AppShell` swaps screens via `AnimatedSwitcher`. `go_router` is a dep but unused. |
| Localization | Hand-rolled — `.arb` files loaded as JSON at runtime via `AppLocalizations.tr(key)`. **No `flutter gen-l10n`.** |
| Other | `image_picker`, `mobile_scanner`, `cached_network_image`, `intl`, `url_launcher`, `uuid` |

SDK constraint: `>=3.0.0 <4.0.0`.

## 3. Repository layout

```
royal-lights/
├── lib/
│   ├── main.dart                 # MaterialApp → InactivityLogoutWrapper(AppShell) | LoginScreen
│   ├── config/
│   │   ├── app_theme.dart        # AppTheme color/text constants
│   │   ├── app_animations.dart   # Shared curves & durations
│   │   ├── supabase_config.dart  # Picks prod/test URL+key based on IS_PROD
│   │   └── secrets.dart          # Hard-coded URLs/anon keys (checked-in)
│   ├── l10n/
│   │   ├── app_he.arb            # Primary
│   │   ├── app_ar.arb
│   │   ├── app_en.arb
│   │   └── app_localizations.dart  # Hand-rolled loader, exposes tr(key)
│   ├── models/                   # Plain Dart classes with fromJson / toJson / copyWith
│   ├── providers/providers.dart  # ALL Riverpod providers live in this single file
│   ├── services/                 # One Service<Domain> + AuthService, WhatsAppService, SessionLocalStorage
│   ├── screens/
│   │   ├── dashboard_screen.dart
│   │   ├── login_screen.dart
│   │   ├── customers/, orders/, payments/, suppliers/, inventory/,
│   │   ├── fixing/, assemblies/
│   └── widgets/                  # Shared UI (see §7)
├── supabase/
│   ├── supabase_schema.sql       # Consolidated reference of the original schema
│   └── migrations/               # YYYYMMDDHHMMSS_<name>.sql, applied via `supabase db push`
├── test/widget_test.dart         # Default scaffold only — treat suite as absent
├── pubspec.yaml
└── analysis_options.yaml         # flutter_lints defaults, no custom rules
```

## 4. Navigation

`lib/widgets/app_shell.dart` renders a collapsible side rail (220 px ↔ 76 px) with these 8 entries in order:

1. Dashboard
2. Customers
3. Orders
4. Fixing (repair tickets)
5. Payments
6. Assemblies
7. Suppliers
8. Inventory

Selected nav index lives in `selectedNavIndexProvider`. The body is an `AnimatedSwitcher`; each screen is keyed by `ValueKey(index)`.

## 5. State management (Riverpod)

Everything is in **`lib/providers/providers.dart`**. Conventions:

```dart
// Service injection
final orderServiceProvider = Provider<OrderService>((ref) =>
    OrderService(ref.watch(supabaseClientProvider)));

// Read-only async list
final ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  return ref.watch(orderServiceProvider).getAll();
});

// Family for per-id queries
final customerOrdersProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, customerId) async { ... });

// Mutable singletons via Notifier
class LocaleNotifier extends Notifier<Locale> { ... }
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
```

After a mutation, **invalidate the affected providers** so dependents refetch:

```dart
await ref.read(orderServiceProvider).update(...);
ref.invalidate(ordersProvider);
ref.invalidate(customerOrdersProvider(customer.id));
```

`authStateProvider` is a `StreamProvider<AuthState>`; signing out automatically rebuilds `main.dart` to show the login screen.

## 6. Localization

Three .arb files plus `AppLocalizations` (custom loader):

```dart
final l10n = AppLocalizations.of(context);
Text(l10n?.tr('cancel') ?? 'Cancel');
```

When you need an inline string that may not be in the .arb yet, the established helper is **`_trOrLocale`** (defined privately per screen):

```dart
_trOrLocale(context, l10n, 'sendOrdersReport',
    en: 'Send orders report', he: 'שלח דוח הזמנות', ar: 'إرسال تقرير الطلبات')
```

It looks up the .arb key first, falling back to the per-locale literal. **Adding a translation = edit all three .arb files** — no codegen step.

RTL is applied globally in `main.dart` based on `localeProvider`.

## 7. Theming & shared widgets

`AppTheme` (in `lib/config/app_theme.dart`) is the single source of truth for color tokens: `primary` (black), `secondary` (gold), `success`, `warning`, `error`, the `surface*` family, `outline*`. **Never hard-code colors** — pick from these.

Standard text style: `GoogleFonts.assistant(fontWeight: ..., fontSize: ..., color: AppTheme.onSurface)`.

Reusable widgets in `lib/widgets/`:

| Widget | What it's for |
|---|---|
| `AppShell` | Top-level scaffold with side rail + animated body |
| `InactivityLogoutWrapper` | 20-min idle → `signOut()`; resets on pointer events |
| `EditorialScreenTitle` | Standard 42 pt page header with gold underline |
| `BrandLogo` | Centred logo PNG with sizing knobs |
| `BarcodeScanDialog` | Mobile-scanner sheet (native + web) |
| `AppLoadingOverlay` | Stacked spinner with optional label |
| `AppAnimatedSquareCheckbox` | Custom rounded checkbox with pulse animation |
| `app_dropdown_styles.dart` | Helpers for `DropdownMenu`: `appDropdownMenuStyle()`, `appDropdownInputDecorationTheme()`, `animatedDropdownDecorationBuilder(...)`, `dropdownLeadingSlot(...)`. **Use these — don't roll a new dropdown style.** |

## 8. Auth & sessions

- Login: email + password via `AuthService.signIn()` (Supabase GoTrue). Min 6-char password.
- Errors are translated from Supabase codes (`invalid_credentials`, `email_not_confirmed`, `rate_limit`, `user_banned`, network timeouts) into friendly Hebrew messages.
- Logout: `ref.read(authServiceProvider).signOut()`.
- **Inactivity logout: 20 minutes**, implemented in `lib/widgets/inactivity_logout_wrapper.dart`. Wraps `AppShell` in `main.dart`. Any `Listener` pointer event resets the timer.
- Session persistence: `SessionLocalStorage` — `window.sessionStorage` on web, in-memory on native. (Means the user is logged out of the native app on every launch.)

## 9. Supabase

### Config
`lib/config/supabase_config.dart` switches between prod and test based on a `IS_PROD` flag in `lib/config/secrets.dart` (checked into the repo — don't paste new secrets there casually).

### Conventions
- **All DB access goes through service classes.** Don't call `Supabase.instance` from a widget.
- Each service exposes a small surface: `getAll`, `getById`, `getByCustomer`, `create`, `update`, `delete`, plus domain-specific helpers (`updateStatus`, `cancelOrder`, `markItemsSupplierReceived`, etc.).
- All write methods accept a `username` for audit columns (`created_by`, `updated_by`).

### Migrations
Drop a new file in `supabase/migrations/`:

```
supabase/migrations/YYYYMMDDHHMMSS_descriptive_name.sql
```

Latest filenames use **2026-MM-DD** timestamps (the project uses a future date convention). Make migrations **idempotent**:

- `CREATE TABLE IF NOT EXISTS …`
- `ALTER TABLE … ADD COLUMN IF NOT EXISTS …`
- `ALTER TYPE … ADD VALUE IF NOT EXISTS '…';`
- For policies, wrap in `do $$ begin if not exists (select 1 from pg_policies …) then create policy … end if; end $$;`

The user applies migrations themselves (`supabase db push` or via dashboard). **Don't try to run them from Claude.**

### Storage
Active bucket: **`inventory-item-photos`** (public read, authenticated write). Use `20260408135000_add_inventory_item_photos_bucket.sql` as the template for any new bucket.

### Row-level security
The modern RLS pattern is in `20260502120000_inventory_items_rls.sql`. Older tables predate it.

## 10. WhatsApp integration

`lib/services/whatsapp_service.dart` calls a Supabase Edge Function named **`whatsapp-sender`** — it does **not** open `wa.me` URLs.

```dart
final ok = await WhatsAppService.sendMessage(phone, message);
```

Phone normalization: strips non-digits, converts Israeli `05X…` → `972…`, appends `@s.whatsapp.net`. The leading `0` rule is critical — don't rewrite it.

The customer-detail screen has the canonical multi-section message builders to copy from:

- `_buildPaymentsReportMessage(...)` — list of payments + account status
- `_buildOrdersReportMessage(...)` — per-order header + items × qty × price + final total + grand total

## 11. Domain notes

### Order statuses (display order, Title Case in DB)
`Active → Preparing → Sent to Supplier → In Assembly → Awaiting Shipping → Handled → Delivered → Canceled`

`OrderStatusExtension.fromString` is case-insensitive and forgiving. `OrderStatusExtension.all` returns them in the canonical display order — use this for filter menus and counts.

### Payment types
`Cash, Credit, Check, Transfer`. Hebrew: מזומן / אשראי / צ׳ק / העברה. The DB enum is `payment_type`.

### Order form (`lib/screens/orders/order_form_screen.dart`)
- ~4 000 LOC, by far the largest file. Read carefully before editing.
- `_isReadOnly` blocks all edits when status is `sentToSupplier` or `canceled` (the per-status enable/disable lives in this getter).
- Items render as `_ItemRow` instances (private class at the bottom of the file).
- VAT is currently hard-coded at 18 %. Discount, image-upload-per-item, and a VAT toggle were prototyped and rolled back — see §13.

### Inventory dialog (`InventoryItemDialog` in `lib/screens/inventory/inventory_screen.dart`)
- Supplier dropdown shows `Supplier.contactName` (the person), falling back to `companyName` if blank.
- Selecting a supplier auto-fills the brand/company field with `Supplier.companyName` and locks it (read-only). Clearing the supplier unlocks it.
- Items can be saved without a supplier (no required-supplier validation).

### Fixing
Repair / warranty tickets. Items can be pulled from the customer's existing orders (linking by `order_item_id`) or entered free-form. Lives under `lib/screens/fixing/`.

## 12. Testing & static analysis

- **Tests**: only `test/widget_test.dart` (Flutter scaffold). The suite is effectively empty — verify by running the app.
- **Lints**: `flutter_lints` defaults, no custom rules.
- **Run `flutter analyze` before declaring a task done.**
- The repo currently has **9 pre-existing info-level lints** that are out of scope:
  - `avoid_print` in `create_user.dart` (×7) and `lib/services/whatsapp_service.dart` (×1)
  - `curly_braces_in_flow_control_structures` in `lib/screens/inventory/inventory_screen.dart:185`
- **Goal: don't introduce new ones.** Don't fix the existing 9 unless explicitly asked.

## 13. Things rolled back — don't auto-implement

The following were prototyped on 2026-05-05 and reverted on 2026-05-07. Do **not** re-add unless the user asks:

- VAT ON/OFF toggle on the order form (`Order.vatEnabled` field, totals card switch)
- Discount-percentage field on the order form (`Order.discountPercentage`)
- Manual image upload for individual order items (`OrderService.uploadOrderItemPhoto`, `order-item-photos` bucket)
- Brand-from-existing-inventory dynamic dropdown on the inventory dialog (current behaviour: brand follows supplier company name — see §11)
- Locking the order form fully on `Preparing` status (current behaviour: only `sentToSupplier` / `canceled` lock)

The corresponding migrations were applied to the DB even though the Dart code was reverted, so columns/buckets/enum values may exist on the server. Treat them as latent and ignored.

## 14. Ground rules

- **Don't create new top-level Markdown / README files** without being asked. This `CLAUDE.md` is the exception.
- **Don't run `flutter gen-l10n`** — localisation is hand-rolled.
- **Don't modify `lib/config/secrets.dart`** casually.
- **Don't edit existing migrations.** Always add a new dated file.
- **Don't call `Supabase.instance` from widgets.** Go through a service.
- **Confirm before destructive git ops** (force push, reset --hard, branch -D).
- **Never bypass `_isReadOnly`** in the order form when fixing a UI bug — the read-only state is the spec, not a side effect.
- **Use `AppTheme` and `_trOrLocale`** instead of hard-coded colors / strings.

## 15. Quick "where do I start" map

| I want to… | Open |
|---|---|
| Add a navigation entry | `lib/widgets/app_shell.dart` (search for `_NavItem` list around line 68) |
| Add a Riverpod provider | `lib/providers/providers.dart` |
| Add a translation | All three `lib/l10n/*.arb` files |
| Add an order-related field | `lib/models/order.dart` + a new migration + write paths in `lib/screens/orders/order_form_screen.dart` (`_saveOrder`) |
| Add a payment type | `lib/models/payment.dart` enum + `dbValue` + `fromString` + every exhaustive `switch (paymentType)` in `payments_screen.dart` and `customer_detail_screen.dart` + .arb files + new migration `ALTER TYPE payment_type ADD VALUE …` |
| Send a WhatsApp message | `WhatsAppService.sendMessage(phone, message)` |
| Upload an image | `image_picker` → bytes → `supabase.storage.from(<bucket>).uploadBinary(...)`. Pattern in `inventory_screen.dart:2030+`. |
| Build a styled dropdown | Use the helpers in `lib/widgets/app_dropdown_styles.dart` |
