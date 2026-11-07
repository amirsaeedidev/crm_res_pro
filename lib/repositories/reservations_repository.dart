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

  Future<List<ReservationModel>> getReservations({int page = 1, int pageSize = 15, String? searchQuery, String? status}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('reservations_view').select('*');
      final normalizedStatus = status?.trim();
      if (normalizedStatus != null && normalizedStatus.isNotEmpty && normalizedStatus != 'all') query = query.eq('status', normalizedStatus);
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) {
        final escaped = search.replaceAll('\\', '\\\\').replaceAll(',', r'\,').replaceAll('%', r'\%').replaceAll('_', r'\_');
        query = query.or('customer_name.ilike.%$escaped%,customer_phone.ilike.%$escaped%,table_number.ilike.%$escaped%');
      }
      final rows = await query.order('date', ascending: false).order('time', ascending: false).range((page - 1) * pageSize, page * pageSize - 1);
      return rows.map((row) => ReservationModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch reservations failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت رزروها'));
    }
  }

  Future<void> updateReservationStatus(String id, String newStatus, {String? reason, int? delayMinutes, String? delayNote}) async {
    const allowed = {'pending','confirmed','delayed','arrived','completed','cancelled','no_show'};
    if (!allowed.contains(newStatus)) throw ArgumentError.value(newStatus, 'newStatus', 'Unsupported reservation status');
    final now = DateTime.now().toUtc().toIso8601String();
    final data = <String, dynamic>{'status': newStatus, 'updated_at': now};
    if (newStatus == 'arrived') data['arrived_at'] = now;
    if (newStatus == 'delayed') {
      data['delayed_at'] = now;
      if (delayMinutes != null) data['delay_minutes'] = delayMinutes;
      if (delayNote?.trim().isNotEmpty == true) data['delay_note'] = delayNote!.trim();
    }
    if (newStatus == 'cancelled') {
      if (reason?.trim().isNotEmpty != true) throw ArgumentError('Cancellation reason is required');
      data['cancelled_at'] = now;
      data['cancellation_reason'] = reason!.trim();
    }
    if (newStatus == 'no_show') data['no_show_at'] = now;
    try {
      final rows = await _client.from('reservations').update(data).eq('id', id).select('id');
      if (rows.isEmpty) throw Exception('رزرو پیدا نشد یا مجوز تغییر آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update reservation status failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'تغییر وضعیت رزرو'));
    }
  }

  Future<String> convertReservationToOrder(String reservationId) async {
    try {
      final result = await _client.rpc('convert_reservation_to_order', params: {'p_reservation_id': reservationId});
      if (result == null) throw Exception('شناسه سفارش از سرور دریافت نشد.');
      return result.toString();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Convert reservation to order failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'تبدیل رزرو به سفارش'));
    }
  }

  Future<void> createReservation({required String userId, required String tableId, required int guestCount, required DateTime date, required TimeOfDayValue time, String? note, int durationMinutes = 90}) async {
    if (guestCount < 1) throw ArgumentError.value(guestCount, 'guestCount');
    if (durationMinutes < 15 || durationMinutes > 480) throw ArgumentError.value(durationMinutes, 'durationMinutes');
    try {
      await _ensureSlotAvailable(tableId: tableId, date: date, time: time.value);
      await _client.from('reservations').insert({
        'user_id': userId, 'table_id': tableId, 'guest_count': guestCount,
        'reservation_date': date.toIso8601String().substring(0, 10),
        'reservation_time': time.value, 'duration_minutes': durationMinutes, 'note': note?.trim().isEmpty == true ? null : note?.trim(), 'status': 'pending',
      });
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create reservation failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ثبت رزرو'));
    }
  }

  Future<void> updateReservationDetails({required String id, required String tableId, required int guestCount, required DateTime date, required TimeOfDayValue time, String? note, int durationMinutes = 90}) async {
    if (guestCount < 1) throw ArgumentError.value(guestCount, 'guestCount');
    if (durationMinutes < 15 || durationMinutes > 480) throw ArgumentError.value(durationMinutes, 'durationMinutes');
    try {
      await _ensureSlotAvailable(tableId: tableId, date: date, time: time.value, excludeReservationId: id);
      final rows = await _client.from('reservations').update({
        'table_id': tableId, 'guest_count': guestCount,
        'reservation_date': date.toIso8601String().substring(0, 10),
        'reservation_time': time.value, 'duration_minutes': durationMinutes, 'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id).inFilter('status', ['pending', 'confirmed', 'delayed']).select('id');
      if (rows.isEmpty) throw Exception('فقط رزرو در انتظار قابل ویرایش است یا مجوز ویرایش ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update reservation details failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش رزرو'));
    }
  }

  Future<void> _ensureSlotAvailable({required String tableId, required DateTime date, required String time, String? excludeReservationId}) async {
    final dateValue = date.toIso8601String().substring(0, 10);
    var query = _client.from('reservations').select('id')
      .eq('table_id', tableId).eq('reservation_date', dateValue)
      .eq('reservation_time', time).inFilter('status', ['pending','confirmed','delayed','arrived']);
    if (excludeReservationId != null) query = query.neq('id', excludeReservationId);
    if ((await query.limit(1)).isNotEmpty) throw Exception('برای این میز در این بازه زمانی رزرو فعالی وجود دارد.');
  }

  Future<Set<String>> getTableNumbersReservedToday() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await _client.from('reservations_view').select('table_number,date,status')
        .eq('date', today).inFilter('status', ['pending','confirmed','delayed','arrived']);
      return rows.map<String>((row) => (row['table_number'] ?? '').toString()).where((v) => v.isNotEmpty).toSet();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch todays reserved tables failed', error: e, stackTrace: st);
      return <String>{};
    }
  }

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action باید دسترسی مدیر داشته باشید.';
    if (e.code == '23P01' || e.code == '23505') return 'این میز در بازه زمانی انتخاب‌شده رزرو دیگری دارد.';
    if (e.code == 'PGRST205' || e.code == '42P01') return 'نمای reservations_view در Supabase پیدا نشد.';
    if (e.code == 'PGRST204' || e.code == '42703') return 'ستون‌های فاز ۹ در دیتابیس نصب نشده‌اند.';
    return 'خطا در $action: ${e.message}';
  }
}
