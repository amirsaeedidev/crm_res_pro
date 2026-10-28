import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/ticket_model.dart';

class TicketsRepository {
  final SupabaseClient _client;
  TicketsRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<TicketModel>> getTickets({int page = 1, int pageSize = 20, String? search, String? status}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('tickets').select('*');
      if (status == 'unread') {
        query = query.eq('status', 'open').isFilter('admin_read_at', null);
      } else if (status == 'received') {
        query = query.eq('status', 'open');
      } else if (status != null && status.isNotEmpty && status != 'all') {
        query = query.eq('status', status);
      }
      final normalized = search?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        final safe = normalized.replaceAll('\\', '\\\\').replaceAll(',', r'\,').replaceAll('%', r'\%').replaceAll('_', r'\_');
        query = query.ilike('subject', '%$safe%');
      }
      final rows = await query.order('updated_at', ascending: false).range((page - 1) * pageSize, page * pageSize - 1);
      if (rows.isEmpty) return [];
      final ids = rows.map((r) => r['user_id'].toString()).toSet().toList();
      final userRows = await _client.from('profiles').select('id,first_name,last_name,phone,email').inFilter('id', ids);
      final users = <String, Map<String, dynamic>>{for (final user in userRows) user['id'].toString(): Map<String, dynamic>.from(user)};
      return rows.map((row) {
        final user = users[row['user_id'].toString()] ?? <String, dynamic>{};
        final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
        return TicketModel.fromJson(Map<String, dynamic>.from(row), customerName: name, customerPhone: (user['phone'] ?? '').toString(), customerEmail: (user['email'] ?? '').toString());
      }).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch tickets failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت تیکت‌ها'));
    }
  }

  Future<TicketModel> getTicketById(String id) async {
    try {
      await _client.from('tickets').update({'admin_read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id).isFilter('admin_read_at', null);
      final row = await _client.from('tickets').select('*').eq('id', id).single();
      final uid = row['user_id'].toString();
      final userResponse = await _client.from('profiles').select('id,first_name,last_name,phone,email').eq('id', uid).maybeSingle();
      final user = userResponse == null ? <String, dynamic>{} : Map<String, dynamic>.from(userResponse);
      final messageRows = await _client.from('ticket_messages').select('*').eq('ticket_id', id).order('created_at');
      final senderIds = messageRows.map((m) => m['user_id'].toString()).toSet().toList();
      final senderRows = senderIds.isEmpty ? <Map<String, dynamic>>[] : (await _client.from('profiles').select('id,first_name,last_name,email').inFilter('id', senderIds)).map((e) => Map<String, dynamic>.from(e)).toList();
      final senderMap = <String, Map<String, dynamic>>{for (final s in senderRows) s['id'].toString(): s};
      final messages = messageRows.map((m) {
        final sender = senderMap[m['user_id'].toString()] ?? <String, dynamic>{};
        final name = '${sender['first_name'] ?? ''} ${sender['last_name'] ?? ''}'.trim();
        return TicketMessageModel.fromJson(Map<String, dynamic>.from(m), senderName: name.isEmpty ? (sender['email'] ?? '').toString() : name);
      }).toList();
      final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
      return TicketModel.fromJson(Map<String, dynamic>.from(row), customerName: name, customerPhone: (user['phone'] ?? '').toString(), customerEmail: (user['email'] ?? '').toString(), messages: messages);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch ticket detail failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت جزئیات تیکت'));
    }
  }

  Future<TicketMessageModel> replyToTicket(String ticketId, String message) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('برای پاسخ به تیکت باید ابتدا وارد حساب مدیر شوید.');
    final text = message.trim();
    if (text.isEmpty) throw ArgumentError('متن پاسخ نمی‌تواند خالی باشد.');
    try {
      final dynamic response = await _client.rpc(
        'admin_reply_to_ticket',
        params: {'p_ticket_id': ticketId, 'p_message': text},
      );
      if (response is! Map) {
        throw const FormatException('پاسخ تابع admin_reply_to_ticket معتبر نیست.');
      }
      return TicketMessageModel.fromJson(
        Map<String, dynamic>.from(response),
        senderName: 'مدیر',
      );
    } on PostgrestException catch (e, st) {
      LoggerService.error('Reply to ticket failed', error: e, stackTrace: st);
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw Exception('تابع پاسخ اتمیک تیکت نصب نشده است. فایل supabase/manual/006_admin_reply_to_ticket.sql را اجرا کنید.');
      }
      throw Exception(_friendlyError(e, 'ارسال پاسخ'));
    }
  }

  Future<Map<String, int>> getTicketCounts() async {
    try {
      final response = await _client.rpc('admin_get_ticket_counts');
      if (response is! Map) throw const FormatException('پاسخ شمارنده تیکت نامعتبر است.');
      return response.map((key, value) => MapEntry(key.toString(), (value as num? ?? 0).toInt()));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch ticket counts failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت آمار تیکت‌ها'));
    }
  }

  Future<void> updateTicketStatus(String id, String status) async {
    if (!{'open','answered','closed'}.contains(status)) throw ArgumentError.value(status, 'status');
    try {
      final rows = await _client.from('tickets').update({'status': status, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).select('id');
      if (rows.isEmpty) throw Exception('تیکت پیدا نشد یا مجوز تغییر وضعیت آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update ticket status failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'تغییر وضعیت تیکت'));
    }
  }

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action دسترسی مدیر لازم است. نشست ورود و سیاست‌های RLS را بررسی کنید.';
    if (e.code == 'PGRST205' || e.code == '42P01') return 'جداول tickets یا ticket_messages در دیتابیس پیدا نشدند.';
    return 'خطا در $action: ${e.message}';
  }
}
