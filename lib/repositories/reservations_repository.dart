import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/reservation_model.dart';

class TimeOfDayValue {
  final String value;
  const TimeOfDayValue(this.value);
}

class ReservationsRepository {
  final SupabaseClient _client;
  ReservationsRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<ReservationModel>> getReservations({int page = 1, int pageSize = 1000, String? searchQuery, String? status, String? dateFrom, String? dateTo}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('reservations_view').select('*');
      if (dateFrom != null && dateFrom.isNotEmpty) query = query.gte('date', dateFrom);
      if (dateTo != null && dateTo.isNotEmpty) query = query.lte('date', dateTo);
      final normalizedStatus = status?.trim();
      if (normalizedStatus != null && normalizedStatus.isNotEmpty && normalizedStatus != 'all') query = query.eq('status', normalizedStatus);
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) {
        final escaped = search.replaceAll('\\', '\\\\').replaceAll(',', r'\,').replaceAll('%', r'\%').replaceAll('_', r'\_');
        query = query.or('customer_name.ilike.%$escaped%,customer_phone.ilike.%$escaped%,table_number.ilike.%$escaped%');
      }
      final rows = await query.order('date', ascending: true).order('time', ascending: true).range((page - 1) * pageSize, page * pageSize - 1);
      return rows.map((row) => ReservationModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch reservations failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت رزروها'));
    }
  }

  Future<void> updateReservationStatus(String id, String newStatus) async {
    const allowed = {'pending', 'confirmed', 'completed', 'cancelled'};
    if (!allowed.contains(newStatus)) throw ArgumentError.value(newStatus, 'newStatus', 'Unsupported reservation status');
    try {
      final rows = await _client.from('reservations').update({'status': newStatus, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).select('id');
      if (rows.isEmpty) throw Exception('رزرو پیدا نشد یا مجوز تغییر آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update reservation status failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'تغییر وضعیت رزرو'));
    }
  }


  Future<void> createReservation({required String userId, required String tableId, required int guestCount, required DateTime date, required TimeOfDayValue time, String? note}) async {
    if (guestCount < 1) throw ArgumentError.value(guestCount, 'guestCount');
    try {
      await _ensureSlotAvailable(tableId: tableId, date: date, time: time.value);
      await _client.from('reservations').insert({
        'user_id': userId,
        'table_id': tableId,
        'guest_count': guestCount,
        'reservation_date': date.toIso8601String().substring(0, 10),
        'reservation_time': time.value,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'status': 'pending',
      });
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create reservation failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ثبت رزرو'));
    }
  }

  Future<void> updateReservationDetails({required String id, required String tableId, required int guestCount, required DateTime date, required TimeOfDayValue time, String? note}) async {
    if (guestCount < 1) throw ArgumentError.value(guestCount, 'guestCount');
    try {
      await _ensureSlotAvailable(tableId: tableId, date: date, time: time.value, excludeReservationId: id);
      final rows = await _client.from('reservations').update({
        'table_id': tableId,
        'guest_count': guestCount,
        'reservation_date': date.toIso8601String().substring(0, 10),
        'reservation_time': time.value,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id).select('id');
      if (rows.isEmpty) throw Exception('رزرو پیدا نشد یا مجوز ویرایش آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update reservation details failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش رزرو'));
    }
  }

  Future<void> _ensureSlotAvailable({required String tableId, required DateTime date, required String time, String? excludeReservationId}) async {
    final dateValue = date.toIso8601String().substring(0, 10);
    var query = _client.from('reservations').select('id')
        .eq('table_id', tableId)
        .eq('reservation_date', dateValue)
        .eq('reservation_time', time)
        .inFilter('status', ['pending', 'confirmed']);
    if (excludeReservationId != null) query = query.neq('id', excludeReservationId);
    final conflicts = await query.limit(1);
    if (conflicts.isNotEmpty) {
      throw Exception('برای این میز در تاریخ و ساعت انتخاب‌شده رزرو فعالی وجود دارد.');
    }
  }

  Future<Set<String>> getTableNumbersReservedToday() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await _client.from('reservations_view').select('table_number,date,status').eq('date', today).inFilter('status', ['pending','confirmed']);
      return rows.map<String>((row) => (row['table_number'] ?? '').toString()).where((value) => value.isNotEmpty).toSet();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch todays reserved tables failed', error: e, stackTrace: st);
      // Reservations view may be unavailable to the current role; do not hide the table list.
      return <String>{};
    }
  }

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '23P01') return e.message;
    if (e.code == '23505') return 'این میز در این زمان قبلاً رزرو شده است.';
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action باید با حساب مدیر وارد شده باشید.';
    if (e.code == 'PGRST205' || e.code == '42P01') return 'نمای reservations_view در Supabase پیدا نشد. migrationهای پروژه را بررسی کنید.';
    if (e.code == 'PGRST204' || e.code == '42703' || e.message.contains('reservation_date') || e.message.contains('reservation_time')) {
      return 'ستون‌های زمان‌بندی رزرو در دیتابیس نصب نشده‌اند. فایل supabase/manual/001_complete_reservation_scheduling.sql را در SQL Editor اجرا کنید.';
    }
    return 'خطا در $action: ${e.message}';
  }
}
