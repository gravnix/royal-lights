import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';

/// Opens a full-screen barcode scanner (native and web). Uses [rootNavigator]
/// so it appears above nested routes and dialogs (e.g. inventory editor on iPad).
class BarcodeScanDialog {
  const BarcodeScanDialog._();

  static Future<String?> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _BarcodeScanScreen(l10n: l10n),
      ),
    );
  }
}

class _BarcodeScanScreen extends StatefulWidget {
  const _BarcodeScanScreen({this.l10n});

  final AppLocalizations? l10n;

  @override
  State<_BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<_BarcodeScanScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _trOrLocale(
    BuildContext context,
    String key, {
    required String en,
    required String he,
    required String ar,
  }) {
    final t = widget.l10n?.tr(key) ?? '';
    if (t.isNotEmpty && t != key) return t;
    return switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _trOrLocale(
            context,
            'scanBarcode',
            en: 'Scan barcode',
            he: 'סריקת ברקוד',
            ar: 'مسح الباركود',
          ),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: l10n?.tr('cancel') ?? 'Close',
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            // Web/desktop ignore tap-to-focus; keep off web to match supported platforms.
            tapToFocus: !kIsWeb,
            errorBuilder: (context, error) {
              final isDenied =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              final message = isDenied
                  ? (kIsWeb
                      ? _trOrLocale(
                          context,
                          '__barcodeCameraPermissionWeb',
                          en:
                              'Allow camera access in your browser when prompted, or enable it in the site settings next to the address bar.',
                          he:
                              'אשר גישה למצלמה בדפדפן כשמוצגת הבקשה, או הפעל אותה בהגדרות האתר ליד שורת הכתובת.',
                          ar:
                              'اسمح بالوصول إلى الكاميرا عندما يطلب المتصفح ذلك، أو فعّله من إعدادات الموقع بجانب شريط العنوان.',
                        )
                      : _trOrLocale(
                          context,
                          '__barcodeCameraPermission',
                          en:
                              'Camera access is required to scan barcodes. You can enable it in Settings.',
                          he:
                              'נדרשת גישה למצלמה כדי לסרוק ברקודים. ניתן להפעיל בהגדרות.',
                          ar:
                              'يلزم السماح بالكاميرا لمسح الرموز. يمكنك تفعيل ذلك من الإعدادات.',
                        ))
                  : error.errorDetails?.message ??
                      error.errorCode.message;

              return ColoredBox(
                color: Colors.black,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_off_outlined,
                          color: Colors.white70,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.assistant(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => _controller.start(),
                          child: Text(
                            _trOrLocale(
                              context,
                              '__tryAgain',
                              en: 'Try again',
                              he: 'נסה שוב',
                              ar: 'حاول مرة أخرى',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            onDetect: (capture) {
              if (_handled) return;
              final barcodes = capture.barcodes;
              final raw = barcodes.isNotEmpty ? barcodes.first.rawValue : null;
              if (raw == null || raw.trim().isEmpty) return;
              _handled = true;
              if (context.mounted) {
                Navigator.pop(context, raw.trim());
              }
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      _trOrLocale(
                        context,
                        'scanBarcodeHint',
                        en: 'Point the camera at a barcode',
                        he: 'כוון את המצלמה לברקוד',
                        ar: 'وجّه الكاميرا نحو الباركود',
                      ),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.assistant(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
