import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/table_model.dart';
import 'reservations_repository.dart';

class TablesRepository {
  final SupabaseClient _client;
  final ReservationsRepository _reservationsRepository;
  TablesRepository({SupabaseClient? client, ReservationsRepository? reservationsRepository})
      : _client = client ?? SupabaseService.client,
        _reservationsRepository = reservationsRepository ?? ReservationsRepository(client: client);

  Future<List<TableModel>> getTables() async {
    try {
      final rows = await _client.from('restaurant_tables').select('*').order('table_number');
      final reservedNumbers = await _reservationsRepository.getTableNumbersReservedToday();
      final activeOrders = await _client.from('orders').select('id,table_id,status').inFilter('status', ['pending','confirmed','preparing','ready','out_for_delivery']);
      final orderByTable = <String, String>{};
      for (final order in activeOrders) {
        final tableId = order['table_id']?.toString();
        if (tableId != null && tableId.isNotEmpty) orderByTable.putIfAbsent(tableId, () => order['id'].toString());
      }
      return rows.map((row) {
        final map = Map<String, dynamic>.from(row);
        final number = (map['table_number'] ?? '').toString();
        final activeOrderId = orderByTable[map['id'].toString()];
        final occupied = (map['is_occupied'] as bool? ?? false) || activeOrderId != null;
        map['status'] = occupied ? 'occupied' : (reservedNumbers.contains(number) ? 'reserved' : 'free');
        map['current_order_id'] = activeOrderId;
        return TableModel.fromJson(map);
      }).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch tables failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت میزها'));
    }
  }

  Future<TableModel> createTable({required int tableNumber, required int capacity, bool isActive = true}) async {
    try {
      final row = await _client.from('restaurant_tables').insert({'table_number': tableNumber, 'capacity': capacity, 'is_active': isActive}).select().single();
      return TableModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create table failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ایجاد میز'));
    }
  }

  Future<TableModel> updateTable(String id, {int? tableNumber, int? capacity, bool? isActive}) async {
    final data = <String, dynamic>{};
    if (tableNumber != null) data['table_number'] = tableNumber;
    if (capacity != null) data['capacity'] = capacity;
    if (isActive != null) data['is_active'] = isActive;
    if (data.isEmpty) throw ArgumentError('No table fields to update');
    try {
      final row = await _client.from('restaurant_tables').update(data).eq('id', id).select().single();
      return TableModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update table failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش میز'));
    }
  }

  /// `tables` view has no status/current_order_id columns. Only is_occupied exists.
  Future<void> updateTableStatus(String id, String status, String? currentOrderId) async {
    if (!{'free', 'occupied'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Reservation status is derived from reservations; only free/occupied can be set manually.');
    }
    try {
      final table = await _client.from('restaurant_tables').select('id,table_number').eq('id', id).single();
      if (status == 'free') {
        final active = await _client.from('orders').select('id').eq('table_id', id).inFilter('status', ['pending','confirmed','preparing','ready','out_for_delivery']).limit(1);
        if (active.isNotEmpty) throw Exception('این میز به سفارش فعال متصل است؛ ابتدا سفارش را تکمیل یا لغو کنید.');
      }
      await _client.from('restaurant_tables').update({'is_occupied': status == 'occupied', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
      if (currentOrderId != null && status == 'occupied') {
        await _client.from('orders').update({'table_id': id, 'table_number': table['table_number'], 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', currentOrderId);
      }
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update table status failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'تغییر وضعیت میز'));
    }
  }

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action باید دسترسی مدیر داشته باشید.';
    if (e.code == '23505') return 'شمارهٔ میز تکراری است.';
    if (e.code == '23514') return 'ظرفیت میز باید بیشتر از صفر باشد.';
    return 'خطا در $action: ${e.message}';
  }
}
