import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../core/services/logger_service.dart';
import '../models/banner_model.dart';

class BannersRepository {
  final SupabaseClient _client;
  BannersRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<BannerModel>> getBanners({int page = 1, int pageSize = 15, String? searchQuery}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('banners').select('*');
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) query = query.ilike('title', '%${search.replaceAll('%', r'\%').replaceAll('_', r'\_')}%');
      final rows = await query.order('sort_order').order('created_at', ascending: false).range((page - 1) * pageSize, page * pageSize - 1);
      return rows.map((row) => BannerModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch banners failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت بنرها'));
    }
  }

  Future<BannerModel> getBannerById(String id) async {
    try {
      final row = await _client.from('banners').select('*').eq('id', id).single();
      return BannerModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch banner by ID failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت بنر'));
    }
  }

  Future<BannerModel> createBanner(Map<String, dynamic> data) async {
    try {
      final row = await _client.from('banners').insert(_normalize(data)).select().single();
      return BannerModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create banner failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ایجاد بنر'));
    }
  }

  Future<BannerModel> updateBanner(String id, Map<String, dynamic> data) async {
    try {
      final row = await _client.from('banners').update(_normalize(data)).eq('id', id).select().single();
      return BannerModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update banner failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش بنر'));
    }
  }

  Future<void> deleteBanner(String id) async {
    try { await _client.from('banners').delete().eq('id', id); }
    on PostgrestException catch (e, st) {
      LoggerService.error('Delete banner failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'حذف بنر'));
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> source) {
    final data = Map<String, dynamic>.from(source);
    if (data.containsKey('display_order')) data['sort_order'] = data.remove('display_order');
    for (final key in ['id','emoji','action_url','is_deleted','start_date','end_date','created_at','updated_at']) { data.remove(key); }
    data.removeWhere((key, value) => !const {'title','subtitle','promo_title','discount_code','logo_url','image_url','sort_order','is_active'}.contains(key));
    return data;
  }
  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action دسترسی مدیر لازم است.';
    return 'خطا در $action: ${e.message}';
  }
}
