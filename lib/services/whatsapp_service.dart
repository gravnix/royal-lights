import 'package:supabase_flutter/supabase_flutter.dart';

class WhatsAppService {
  static final _supabase = Supabase.instance.client;

  /// Normalizes a raw phone string to WhatsApp JID format:
  /// `972XXXXXXXXX@s.whatsapp.net`
  static String _toJid(String raw) {
    // Strip everything except digits
    String digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    // Convert local Israeli format (05X…) to international (9725X…)
    if (digits.startsWith('0')) {
      digits = '972${digits.substring(1)}';
    } else if (!digits.startsWith('972')) {
      digits = '972$digits';
    }
    return '$digits@s.whatsapp.net';
  }

  /// Sends a WhatsApp message via the Supabase Edge Function.
  /// [phone] can be in any format — it will be normalized to JID automatically.
  static Future<bool> sendMessage(String phone, String message) async {
    final jid = _toJid(phone);
    try {
      final response = await _supabase.functions.invoke(
        'whatsapp-sender',
        body: {
          'to': jid,
          'message': message,
        },
      );

      return response.status == 200;
    } catch (e) {
      print('WhatsApp Error: $e');
      return false;
    }
  }

  /// Helper to send Order Ready notification to a Customer
  static Future<bool> sendCustomerOrderReady(
      String phone, String customerName, String orderId) {
    final text =
        "Hello $customerName! Great news, your order (#$orderId) is ready for pickup/delivery. Thank you for choosing Royal Lights!";
    return sendMessage(phone, text);
  }

  /// Helper to send new Purchase Order to a Supplier
  static Future<bool> sendSupplierPurchaseOrder(
      String phone, String supplierName, String orderId) {
    final text =
        "Hello $supplierName, we have a new Purchase Order (#$orderId) ready for you from Royal Lights. Please review it at your earliest convenience.";
    return sendMessage(phone, text);
  }
}
