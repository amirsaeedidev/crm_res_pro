import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/order_model.dart';

class OrdersRepository {
  final SupabaseClient _client;
  OrdersRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<OrderModel>> getOrders({int page = 1, int pageSize = 20, String? searchQuery, String? status}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('orders_view').select('*');
      final normalizedStatus = status?.trim();
      if (normalizedStatus != null && normalizedStatus.isNotEmpty && normalizedStatus != 'all') query = query.eq('status', normalizedStatus);
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) {
        // `orders_view.id` is UUID; PostgreSQL does not support `ilike` on UUID.
        // Search names/phone textually, and only search IDs by exact UUID.
        final uuidPattern = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        );
        if (uuidPattern.hasMatch(search)) {
          query = query.eq('id', search);
        } else {
          final escaped = search
              .replaceAll('\\', '\\\\')
              .replaceAll(',', r'\,')
              .replaceAll('(', r'\(')
              .replaceAll(')', r'\)')
              .replaceAll('%', r'\%')
              .replaceAll('_', r'\_');
          query = query.or(
            'customer_name.ilike.%$escaped%,customer_phone.ilike.%$escaped%',
          );
        }
      }
      final rows = await query.order('created_at', ascending: false).range((page - 1) * pageSize, page * pageSize - 1);
      return rows.map((row) => OrderModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch orders failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت سفارش‌ها'));
    }
  }

  Future<OrderModel> getOrderById(String id) async {
    try {
      // Both requests depend only on the requested ID, so run them in parallel
      // and save one network round-trip on the order-details screen.
      final responses = await Future.wait<dynamic>([
        _client.from('orders_view').select('*').eq('id', id).single(),
        _client.from('order_items').select('*, products(name)').eq('order_id', id).order('created_at'),
      ]);
      final row = responses[0] as Map<String, dynamic>;
      final itemRows = responses[1] as List<dynamic>;
      final json = Map<String, dynamic>.from(row)
        ..['order_items'] = itemRows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
      return OrderModel.fromJson(json);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch order detail failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت جزئیات سفارش'));
    }
  }

  Future<List<OrderModel>> getOrdersForCustomer(String userId, {int limit = 20}) async {
    try {
      final rows = await _client.from('orders_view').select('*').eq('user_id', userId).order('created_at', ascending: false).limit(limit);
      return rows.map((row) => OrderModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customer orders failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت سفارش‌های مشتری'));
    }
  }

  Future<void> updateOrderStatus(String id, String newStatus) async {
    const allowed = {'pending','confirmed','preparing','ready','out_for_delivery','completed','cancelled'};
    if (!allowed.contains(newStatus)) throw ArgumentError.value(newStatus, 'newStatus', 'Unsupported order status');
    try {
      final data = <String, dynamic>{'status': newStatus, 'updated_at': DateTime.now().toUtc().toIso8601String()};
      if (newStatus == 'completed') data['completed_at'] = DateTime.now().toUtc().toIso8601String();
      final rows = await _client.from('orders').update(data).eq('id', id).select('id');
      if (rows.isEmpty) throw Exception('سفارش پیدا نشد یا مجوز تغییر آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update order status failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'تغییر وضعیت سفارش'));
    }
  }

  Future<void> updateOrderMetadata(String id, Map<String, dynamic> data) async {
    const allowedFields = {'estimated_ready_minutes','admin_note','assigned_staff_id'};
    final filtered = Map<String, dynamic>.from(data)..removeWhere((key, value) => !allowedFields.contains(key));
    if (filtered.isEmpty) return;
    filtered['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      final rows = await _client.from('orders').update(filtered).eq('id', id).select('id');
      if (rows.isEmpty) throw Exception('سفارش پیدا نشد یا مجوز ویرایش آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update order metadata failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش اطلاعات سفارش'));
    }
  }

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action باید با حساب مدیر وارد شده باشید.';
    if (e.code == 'PGRST205' || e.code == '42P01') return 'جدول یا نمای موردنیاز در دیتابیس پیدا نشد.';
    if (e.code == '23514') return 'وضعیت یا مقدار ارسالی با محدودیت دیتابیس سازگار نیست.';
    return 'خطا در $action: ${e.message}';
  }
}
