import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fixing_ticket.dart';

class FixingService {
  final SupabaseClient _client;
  FixingService(this._client);

  Future<List<FixingTicket>> getOpenTickets() async {
    final data = await _client
        .from('fixing_tickets')
        .select('*, customers(card_name, customer_name), fixing_ticket_items(*)')
        .eq('status', FixingTicketStatus.pending.dbValue)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => FixingTicket.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markFixed(String ticketId, String username) async {
    await _client.from('fixing_tickets').update({
      'status': FixingTicketStatus.fixed.dbValue,
      'updated_by': username,
      'fixed_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }

  Future<void> deleteTicket(String ticketId) async {
    // `fixing_ticket_items` rows are deleted via ON DELETE CASCADE.
    await _client.from('fixing_tickets').delete().eq('id', ticketId);
  }

  Future<void> createTicket({
    required String customerId,
    required String username,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Fixing ticket must include at least one item');
    }

    final ticket = await _client
        .from('fixing_tickets')
        .insert({
          'customer_id': customerId,
          'status': FixingTicketStatus.pending.dbValue,
          'created_by': username,
          'updated_by': username,
        })
        .select()
        .single();

    final ticketId = ticket['id'] as String;
    final itemsWithTicketId = items
        .map((m) => {
              ...m,
              'ticket_id': ticketId,
              'created_by': username,
              'updated_by': username,
            })
        .toList();

    await _client.from('fixing_ticket_items').insert(itemsWithTicketId);
  }
}

