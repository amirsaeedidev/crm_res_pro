import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';

class InventoryRepository {
  final SupabaseClient _client;
  InventoryRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<Map<String, dynamic>>> getMaterials() async {
    final rows = await _client.from('inventory_materials').select('*').order('name').limit(250);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final rows = await _client.from('products').select('id,name,price,is_active').eq('is_active', true).order('name').limit(300);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getRecipes() async {
    final rows = await _client.from('product_recipes').select('id,product_id,material_id,quantity_per_product,notes,products(name),inventory_materials(name,unit,unit_cost)').order('created_at', ascending: false).limit(500);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getTransactions() async {
    final rows = await _client.from('inventory_transactions').select('id,material_id,transaction_type,quantity_delta,unit_cost,total_cost,order_id,reason,created_at,inventory_materials(name,unit)').order('created_at', ascending: false).limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<void> saveMaterial({String? id, required String name, required String? sku, required String unit, required double unitCost, required double reorderLevel, required String notes}) async {
    if (name.trim().isEmpty) throw ArgumentError('نام ماده اولیه الزامی است.');
    if (unitCost < 0 || reorderLevel < 0 || !unitCost.isFinite || !reorderLevel.isFinite) throw ArgumentError('هزینه و حد هشدار باید معتبر باشند.');
    final payload = <String, dynamic>{
      'name': name.trim(), 'sku': sku?.trim().isEmpty ?? true ? null : sku!.trim(), 'unit': unit,
      'unit_cost': unitCost, 'reorder_level': reorderLevel, 'notes': notes.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    // Stock quantity is intentionally omitted: database column grants forbid
    // changing it directly. Inventory movements go through audited RPCs.
    if (id != null) payload['id'] = id;
    try {
      await _client.from('inventory_materials').upsert(payload, onConflict: 'id');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Save inventory material failed', error: e, stackTrace: st);
      throw Exception(e.code == '23505' ? 'کد انبار تکراری است.' : 'ذخیره ماده اولیه ناموفق بود: ${e.message}');
    }
  }

  Future<void> receiveStock({required String materialId, required double quantity, required double unitCost, required String reason}) async {
    await _client.rpc('admin_receive_inventory', params: {'p_material_id': materialId, 'p_quantity': quantity, 'p_unit_cost': unitCost, 'p_reason': reason.trim()});
  }

  Future<void> adjustStock({required String materialId, required double quantityDelta, required String reason}) async {
    await _client.rpc('admin_adjust_inventory', params: {'p_material_id': materialId, 'p_quantity_delta': quantityDelta, 'p_reason': reason.trim()});
  }

  Future<void> recordMovement({required String materialId, required double quantity, required String transactionType, required String reason}) async {
    if (quantity <= 0 || !quantity.isFinite) throw ArgumentError('مقدار باید بزرگ‌تر از صفر باشد.');
    if (!{'waste', 'return'}.contains(transactionType)) throw ArgumentError('نوع گردش انبار نامعتبر است.');
    if (reason.trim().isEmpty) throw ArgumentError('شرح گردش انبار الزامی است.');
    await _client.rpc('admin_record_inventory_movement', params: {
      'p_material_id': materialId,
      'p_quantity': quantity,
      'p_transaction_type': transactionType,
      'p_reason': reason.trim(),
    });
  }

  Future<void> saveRecipe({String? id, required String productId, required String materialId, required double quantity, required String notes}) async {
    if (quantity <= 0 || !quantity.isFinite) throw ArgumentError('مقدار مصرف هر غذا باید بزرگ‌تر از صفر باشد.');
    final payload = <String, dynamic>{
      'product_id': productId,
      'material_id': materialId,
      'quantity_per_product': quantity,
      'notes': notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (id != null) {
      // An edit may change the product/material pair; update by primary key
      // rather than conflicting on the old composite key.
      await _client.from('product_recipes').update(payload).eq('id', id);
    } else {
      await _client.from('product_recipes').upsert(payload, onConflict: 'product_id,material_id');
    }
  }

  Future<void> deleteRecipe(String id) async => _client.from('product_recipes').delete().eq('id', id);
}
