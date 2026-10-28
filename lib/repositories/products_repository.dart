import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../core/services/logger_service.dart';
import '../models/product_model.dart';

class ProductsRepository {
  final SupabaseClient _client;
  ProductsRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<ProductModel>> getProducts({int page = 1, int pageSize = 20, String? searchQuery, String? categoryId}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      final start = (page - 1) * pageSize;
      var query = _client.from('products').select('*, categories(name)');
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) query = query.ilike('name', '%${_escapeLike(search)}%');
      if (categoryId != null && categoryId.isNotEmpty) query = query.eq('category_id', categoryId);
      final rows = await query.order('created_at', ascending: false).range(start, start + pageSize - 1);
      return rows.map((row) => ProductModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch products failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت محصولات'));
    }
  }

  Future<ProductModel> getProductById(String id) async {
    try {
      final row = await _client.from('products').select('*, categories(name)').eq('id', id).single();
      return ProductModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch product by ID failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت محصول'));
    }
  }

  Future<ProductModel> createProduct(Map<String, dynamic> data) async {
    try {
      final row = await _client.from('products').insert(_normalize(data)).select('*, categories(name)').single();
      return ProductModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create product failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ایجاد محصول'));
    }
  }

  Future<ProductModel> updateProduct(String id, Map<String, dynamic> data) async {
    try {
      final row = await _client.from('products').update(_normalize(data)).eq('id', id).select('*, categories(name)').single();
      return ProductModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update product failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش محصول'));
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _client.from('products').delete().eq('id', id);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Delete product failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'حذف محصول'));
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> input) {
    final data = Map<String, dynamic>.from(input);
    if (data.containsKey('status')) data['is_active'] = data.remove('status') == 'active';
    // The existing DB has no inventory or per-product discount columns.
    for (final key in ['discounted_price', 'discountedPrice', 'stock', 'status', 'category_name', 'categories', 'id', 'created_at']) {
      data.remove(key);
    }
    data.removeWhere((key, value) => !const {'name','description','about_dish','labels','discount_percent','price','image_url','is_active','is_available','unavailable_reason','is_popular','rating','review_count','category_id'}.contains(key));
    if (data['price'] is num) data['price'] = (data['price'] as num).round();
    if (data['discount_percent'] is num) data['discount_percent'] = (data['discount_percent'] as num).clamp(0, 100).toDouble();
    if (data['labels'] is List) data['labels'] = (data['labels'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet().toList();
    return data;
  }

  String _escapeLike(String value) => value.replaceAll('\\', '\\\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'مجوز لازم برای $action ندارید. نشست ورود و نقش مدیر را بررسی کنید.';
    if (e.code == '23503') return 'دسته‌بندی انتخاب‌شده وجود ندارد یا محصول در سفارش ثبت‌شده استفاده شده است.';
    if (e.code == '23514') return 'یکی از مقادیر محصول با محدودیت‌های دیتابیس سازگار نیست.';
    return 'خطا در $action: ${e.message}';
  }
}
