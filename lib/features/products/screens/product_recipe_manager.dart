import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';

class ProductRecipeManager extends StatefulWidget {
  final String productId;
  const ProductRecipeManager({super.key, required this.productId});
  @override
  State<ProductRecipeManager> createState() => _ProductRecipeManagerState();
}

class _ProductRecipeManagerState extends State<ProductRecipeManager> {
  final _client = SupabaseService.client;
  bool _loading = true;
  bool _saving = false;
  List<Map<String,dynamic>> _materials = [];
  List<Map<String,dynamic>> _recipe = [];
  String? _error;

  @override
  void initState() { super.initState(); unawaited(_load()); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _client.from('inventory_materials').select('id,name,unit,unit_cost,quantity_on_hand').eq('is_active',true).order('name').limit(500),
        _client.from('product_recipes').select('id,material_id,quantity_per_product,notes,inventory_materials(name,unit,unit_cost,quantity_on_hand)').eq('product_id',widget.productId).order('created_at'),
      ]);
      if(!mounted) return;
      setState(() {
        _materials=(results[0] as List).map((x)=>Map<String,dynamic>.from(x)).toList();
        _recipe=(results[1] as List).map((x) {
          final row=Map<String,dynamic>.from(x);
          row['quantity_per_product']=(row['quantity_per_product'] as num).toDouble();
          return row;
        }).toList();
      });
    } catch(e) { if(mounted) setState(()=>_error=e.toString()); }
    finally { if(mounted) setState(()=>_loading=false); }
  }

  String _unit(String? unit) {
    switch(unit) {
      case 'g': return 'گرم';
      case 'kg': return 'کیلوگرم';
      case 'ml': return 'میلی‌لیتر';
      case 'l': return 'لیتر';
      case 'unit': return 'عدد';
      default: return unit ?? '';
    }
  }

  String _money(dynamic v) {
    final n=v is num?v:num.tryParse('$v')??0;
    return n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>'٬');
  }

  Future<void> _save() async {
    if(_recipe.any((r)=>(r['quantity_per_product'] as num)<=0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('مقدار مصرف هر ماده باید بیشتر از صفر باشد.')));
      return;
    }
    setState(()=>_saving=true);
    try {
      await _client.rpc('admin_set_product_recipe',params:{
        'p_product_id':widget.productId,
        'p_items':_recipe.map((r)=>{'material_id':r['material_id'],'quantity_per_product':r['quantity_per_product'],'notes':r['notes']??''}).toList(),
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دستور مصرف غذا ذخیره شد.')));
      await _load();
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('ذخیره دستور مصرف ناموفق بود: $e')));
    } finally { if(mounted) setState(()=>_saving=false); }
  }

  @override
  Widget build(BuildContext context) {
    if(_loading) return const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()));
    final selected=_recipe.map((r)=>r['material_id'].toString()).toSet();
    final available=_materials.where((m)=>!selected.contains(m['id'].toString())).toList();
    final cost=_recipe.fold<double>(0,(sum,r) {
      final m=_materials.where((m)=>m['id'].toString()==r['material_id'].toString()).firstOrNull;
      return sum+((r['quantity_per_product'] as num).toDouble()*(m?['unit_cost'] as num? ?? 0).toDouble());
    });
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(_error!=null) Text('بارگذاری مواد اولیه ناموفق بود: $_error',style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const Text('مواد مصرفی برای تولید یک پرس غذا را وارد کنید. مقدارها باید با واحد پایه ماده اولیه هماهنگ باشند.',style:TextStyle(fontSize:13)),
      const SizedBox(height:8),
      if(_recipe.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('هنوز دستور مصرفی ثبت نشده است. تا زمان ثبت دستور مصرف، کنترل موجودی این غذا بر اساس مواد اولیه انجام نمی‌شود.')),
      ..._recipe.asMap().entries.map((entry) {
        final i=entry.key; final row=entry.value;
        final material=_materials.where((m)=>m['id'].toString()==row['material_id'].toString()).firstOrNull;
        return Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
          Row(children:[
            Expanded(child:Text(material?['name']?.toString()??'ماده اولیه حذف‌شده',style:const TextStyle(fontWeight:FontWeight.w700))),
            Text(_unit(material?['unit']?.toString())),
            IconButton(tooltip:'حذف از دستور مصرف',onPressed:_saving?null:()=>setState(()=>_recipe.removeAt(i)),icon:const Icon(Icons.delete_outline,color:Colors.red)),
          ]),
          Row(children:[
            Expanded(child:TextFormField(
              key:ValueKey('recipe-${row['material_id']}'),
              initialValue:(row['quantity_per_product'] as num).toString(),
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:const InputDecoration(labelText:'مقدار مصرف برای یک پرس'),
              onChanged:(v)=>row['quantity_per_product']=double.tryParse(v)??0,
            )),
            const SizedBox(width:12),
            Expanded(child:Text('موجودی فعلی: ${material?['quantity_on_hand']??'—'} ${_unit(material?['unit']?.toString())}\nبهای واحد: ${_money(material?['unit_cost'])} تومان',style:const TextStyle(fontSize:12))),
          ]),
        ])));
      }),
      if(available.isNotEmpty) Align(alignment:Alignment.centerRight,child:TextButton.icon(
        onPressed: _saving ? null : () => setState(() => _recipe.add({'material_id': available.first['id'].toString(), 'quantity_per_product': 1.0, 'notes': ''})),
        icon:const Icon(Icons.add),label:const Text('افزودن ماده اولیه'),
      )),
      const SizedBox(height:8),
      Text('بهای مواد اولیه هر پرس (برآورد): ${_money(cost)} تومان',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      if(_materials.isEmpty) const Text('ابتدا در بخش انبارداری مواد اولیه را تعریف کنید.'),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save_outlined),label:Text(_saving?'در حال ذخیره…':'ذخیره دستور مصرف')),
    ]);
  }
}
