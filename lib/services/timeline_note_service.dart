import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/timeline_note.dart';

class TimelineNoteService {
  final SupabaseClient _client;
  TimelineNoteService(this._client);

  Future<List<TimelineNote>> getAll() async {
    final data =
        await _client.from('timeline_notes').select().order('note_date');
    return (data as List).map((e) => TimelineNote.fromJson(e)).toList();
  }

  Future<TimelineNote> create(TimelineNote note) async {
    final data = await _client
        .from('timeline_notes')
        .insert(note.toJson())
        .select()
        .single();
    return TimelineNote.fromJson(data);
  }

  Future<TimelineNote> update(String id, Map<String, dynamic> updates) async {
    final data = await _client
        .from('timeline_notes')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return TimelineNote.fromJson(data);
  }

  Future<void> delete(String id) async {
    await _client.from('timeline_notes').delete().eq('id', id);
  }
}
