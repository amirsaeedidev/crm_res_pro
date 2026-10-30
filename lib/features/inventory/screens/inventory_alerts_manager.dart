import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';
import '../utils/inventory_unit_converter.dart';

class InventoryAlertsManager extends StatefulWidget {
  const InventoryAlertsManager({super.key});
  @override
  State<InventoryAlertsManager> createState() => _InventoryAlertsManagerState();
}
class _InventoryAlertsManagerState extends State<InventoryAlertsManager> {
  final _client = SupabaseService.client;
  bool _loading=true, _saving=false, _lowEnabled=true, _nearEnabled=true, _zeroEnabled=true;
  double _defaultLevel=1, _multiplier=1.5;
  List<Map<String,dynamic>> _materials=[];
  String? _error;
  @override
  void initState(){super.initState();unawaited(_load());}
  num _num(dynamic v,[num fallback=0])=>v is num?v:num.tryParse('$v')??fallback;
  String _digits(Object? value){var s=value.toString();const en='0123456789',fa='۰۱۲۳۴۵۶۷۸۹';for(var i=0;i<10;i++){s=s.replaceAll(en[i],fa[i]);}return s;}
  String _money(dynamic v)=>_digits(_num(v).toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>'٬'));
  String _unit(dynamic u)=>const {'g':'گرم','kg':'کیلوگرم','ml':'میلی‌لیتر','l':'لیتر','unit':'عدد','pack':'بسته','box':'جعبه'}[u?.toString()]??'واحد';
  double _threshold(Map<String,dynamic> m) {
    final override=_num(m['reorder_level']).toDouble();
    return override>0 ? override : _defaultLevel;
  }
  Future<void> _load() async {
    setState((){_loading=true;_error=null;});
    try{
      final r=await Future.wait([
        _client.from('inventory_alert_settings').select('*').eq('id',true).maybeSingle(),
        _client.from('inventory_materials').select('id,name,unit,quantity_on_hand,reorder_level,unit_cost').order('name').limit(500),
      ]);
      if(!mounted)return;
      final s=(r[0] as Map<String,dynamic>?)??<String,dynamic>{};
      setState((){
        _defaultLevel=_num(s['default_reorder_level'],1).toDouble();
        _multiplier=_num(s['near_empty_multiplier'],1.5).toDouble();
        _lowEnabled=s['show_low_stock_alerts'] as bool? ?? true;
        _nearEnabled=(s['show_near_empty_alerts'] as bool?) ?? true;
        _zeroEnabled=(s['include_zero_stock'] as bool?) ?? true;
        _materials=(r[1] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
      });
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  List<Map<String,dynamic>> get _low=>_materials.where((m){final q=_num(m['quantity_on_hand']),l=_threshold(m);return _lowEnabled&&(_zeroEnabled?q<=l:q>0&&q<=l);}).toList();
  List<Map<String,dynamic>> get _near=>_materials.where((m){final q=_num(m['quantity_on_hand']),l=_threshold(m);return _nearEnabled&&q>l&&q<=l*_multiplier;}).toList();
  Future<void> _saveSettings() async {
    setState(()=>_saving=true);
    try{
      await _client.from('inventory_alert_settings').upsert({'id':true,'default_reorder_level':_defaultLevel,'near_empty_multiplier':_multiplier,'show_low_stock_alerts':_lowEnabled,'show_near_empty_alerts':_nearEnabled,'include_zero_stock':_zeroEnabled,'updated_by':_client.auth.currentUser?.id,'updated_at':DateTime.now().toUtc().toIso8601String()});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تنظیمات هشدار ذخیره شد.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('ذخیره تنظیمات ناموفق بود: $e')));}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  Future<void> _editThreshold(Map<String,dynamic> m) async {
    final c=TextEditingController(text:_threshold(m).toString());
    final v=await showDialog<double>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('حد هشدار: ${m['name']}'),
      content:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'حداقل موجودی (${_unit(m['unit'])})',helperText:'۰ = استفاده از حد پیش‌فرض')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('انصراف')),FilledButton(onPressed:(){final n=InventoryUnitConverter.parseLocalizedNumber(c.text);if(n!=null&&n>=0)Navigator.pop(ctx,n);},child:const Text('ذخیره'))]));
    c.dispose();if(v==null)return;
    try{await _client.from('inventory_materials').update({'reorder_level':v}).eq('id',m['id']);await _load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('حد هشدار این ماده به‌روزرسانی شد.')));}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('به‌روزرسانی ناموفق بود: $e')));}
  }
  Widget _section(String title,IconData icon,List<Map<String,dynamic>> rows,Color color)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Icon(icon,color:color),const SizedBox(width:8),Expanded(child:Text('$title (${_digits(rows.length)})',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)))]),
    if(rows.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('موردی برای نمایش وجود ندارد.')),
    ...rows.map((m){final q=_num(m['quantity_on_hand']),l=_threshold(m);return ListTile(contentPadding:EdgeInsets.zero,leading:CircleAvatar(backgroundColor:color.withValues(alpha:.12),child:Icon(icon,color:color)),title:Text(m['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('موجودی: ${_digits(q)} ${_unit(m['unit'])} · حد هشدار: ${_digits(l)} ${_unit(m['unit'])}\nبهای واحد: ${_money(m['unit_cost'])} تومان'),isThreeLine:true,trailing:IconButton(tooltip:'تنظیم حد هشدار',onPressed:()=>_editThreshold(m),icon:const Icon(Icons.tune)));}),
  ])));
  @override
  Widget build(BuildContext context){
    if(_loading)return const Center(child:CircularProgressIndicator());
    return RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(12),children:[
      if(_error!=null)Text('خطا در دریافت هشدارها: $_error',style:TextStyle(color:Theme.of(context).colorScheme.error)),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('تنظیمات هشدار موجودی',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('هشدار کمبود موجودی'),subtitle:const Text('وقتی موجودی به حد هشدار برسد یا کمتر شود.'),value:_lowEnabled,onChanged:(v)=>setState(()=>_lowEnabled=v)),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('هشدار نزدیک به اتمام'),subtitle:Text('وقتی موجودی تا ${_digits(_multiplier.toStringAsFixed(1))} برابر حد هشدار باشد.'),value:_nearEnabled,onChanged:(v)=>setState(()=>_nearEnabled=v)),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('نمایش مواد با موجودی صفر'),value:_zeroEnabled,onChanged:(v)=>setState(()=>_zeroEnabled=v)),
        Text('حد پیش‌فرض هشدار: ${_digits(_defaultLevel)} واحد',style:const TextStyle(fontWeight:FontWeight.w600)),
        Slider(value:_defaultLevel.clamp(0,10000).toDouble(),min:0,max:10000,divisions:1000,label:_digits(_defaultLevel),onChanged:(v)=>setState(()=>_defaultLevel=v)),
        Text('آستانه نزدیک به اتمام: ${_digits(_multiplier.toStringAsFixed(1))} برابر حد هشدار',style:const TextStyle(fontWeight:FontWeight.w600)),
        Slider(value:_multiplier,min:1.1,max:3,divisions:19,label:_digits(_multiplier.toStringAsFixed(1)),onChanged:(v)=>setState(()=>_multiplier=v)),
        Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:_saving?null:_saveSettings,icon:_saving?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save_outlined),label:const Text('ذخیره تنظیمات'))),
      ]))),
      _section('مواد کم‌موجود',Icons.warning_amber_rounded,_low,Colors.red),
      _section('مواد نزدیک به اتمام',Icons.hourglass_bottom_rounded,_near,Colors.orange),
      const Card(child:ListTile(leading:Icon(Icons.info_outline),title:Text('شخصی‌سازی هر ماده'),subtitle:Text('با دکمه تنظیم کنار هر ماده، حد هشدار اختصاصی آن را تغییر دهید. تمام مبالغ بر حسب تومان است.'))),
    ]));
  }
}