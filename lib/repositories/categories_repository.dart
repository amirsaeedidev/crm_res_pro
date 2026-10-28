import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../core/services/logger_service.dart';
import '../models/category_model.dart';

class CategoriesRepository {
  final SupabaseClient _client;
  CategoriesRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<CategoryModel>> getCategories({int page = 1, int pageSize = 20, String? searchQuery}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      final start = (page - 1) * pageSize;
      var query = _client.from('categories').select('*');
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) query = query.ilike('name', '%${_escapeLike(search)}%');
      final rows = await query.order('sort_order').order('created_at', ascending: false).range(start, start + pageSize - 1);
      return rows.map((row) => CategoryModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch categories failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت دسته‌بندی‌ها'));
    }
  }

  Future<CategoryModel> getCategoryById(String id) async {
    try {
      final row = await _client.from('categories').select('*').eq('id', id).single();
      return CategoryModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch category by ID failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت دسته‌بندی'));
    }
  }

  Future<CategoryModel> createCategory(Map<String, dynamic> data) async {
    try {
      final row = await _client.from('categories').insert(_normalize(data)).select().single();
      return CategoryModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create category failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ایجاد دسته‌بندی'));
    }
  }

  Future<CategoryModel> updateCategory(String id, Map<String, dynamic> data) async {
    try {
      final row = await _client.from('categories').update(_normalize(data)).eq('id', id).select().single();
      return CategoryModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update category failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش دسته‌بندی'));
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      await _client.from('categories').delete().eq('id', id);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Delete category failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'حذف دسته‌بندی'));
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> input) {
    final data = Map<String, dynamic>.from(input)..remove('description')..remove('display_order');
    if (input.containsKey('display_order')) data['sort_order'] = input['display_order'];
    data.remove('id');
    data.remove('created_at');
    data.removeWhere((key, value) => !const {'name','image_url','sort_order','is_active','loyalty_points_per_item'}.contains(key));
    return data;
  }

  String _escapeLike(String value) => value.replaceAll('\\', '\\\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'مجوز لازم برای $action ندارید. نشست ورود و نقش مدیر را بررسی کنید.';
    if (e.code == '23503') return 'این دسته‌بندی به محصول متصل است؛ ابتدا محصولات وابسته را به دسته‌بندی دیگری منتقل کنید.';
    if (e.code == '23505') return 'داده‌ای با این مشخصات از قبل ثبت شده است.';
    return 'خطا در $action: ${e.message}';
  }
}
