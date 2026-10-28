import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';

class InventoryStockCountManager extends StatefulWidget {
  const InventoryStockCountManager({super.key});
  @override
  State<InventoryStockCountManager> createState() => _InventoryStockCountManagerState();
}

class _InventoryStockCountManagerState extends State<InventoryStockCountManager> {
  final _client = SupabaseService.client;
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _countControllers = {};
  List<Map<String,dynamic>> _materials = [];
  List<Map<String,dynamic>> _history = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _showAll = true;

  @override
  void initState() { super.initState(); unawaited(_load()); }

  @override
  void dispose() {
    _notes.dispose();
    for (final c in _countControllers.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await Future.wait([
        _client.from('inventory_materials').select('id,name,unit,unit_cost,quantity_on_hand,is_active').eq('is_active',true).order('name').limit(500),
        _client.from('inventory_stock_counts').select('id,count_number,count_date,notes,item_count,discrepancy_count,total_discrepancy_cost,created_at,inventory_stock_count_items(material_id,system_quantity,counted_quantity,difference_quantity,unit_cost,difference_cost,inventory_materials(name,unit))').order('created_at',ascending:false).limit(30),
      ]);
      if (!mounted) return;
      final materials=(result[0] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
      final oldControllers=Map<String,TextEditingController>.from(_countControllers);
      _countControllers.clear();
      for (final m in materials) {
        final id=m['id'].toString();
        _countControllers[id]=oldControllers[id]??TextEditingController(text:'${m['quantity_on_hand']??0}');
      }
      for (final entry in oldControllers.entries) {
        if (!materials.any((m)=>m['id'].toString()==entry.key)) entry.value.dispose();
      }
      setState(() {
        _materials=materials;
        _history=(result[1] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
      });
    } catch(e) { if(mounted) setState(()=>_error=e.toString()); }
    finally { if(mounted) setState(()=>_loading=false); }
  }

  num _num(dynamic v)=>v is num?v:num.tryParse('$v')??0;
  String _digits(Object? value) {
    const latin='0123456789', persian='۰۱۲۳۴۵۶۷۸۹';
    var s=value?.toString()??'';
    for(var i=0;i<10;i++) { s=s.replaceAll(latin[i],persian[i]); }
    return s;
  }
  String _qty(dynamic v) {
    final n=_num(v);
    return _digits(n.toStringAsFixed(n.truncateToDouble()==n?0:3).replaceAll('.', '٫'));
  }
  String _money(dynamic v)=>_digits(_num(v).toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>'٬'));
  String _unit(dynamic v)=>const {'g':'گرم','kg':'کیلوگرم','ml':'میلی‌لیتر','l':'لیتر','unit':'عدد','pack':'بسته','box':'جعبه'}[v?.toString()]??(v?.toString()??'واحد');

  Future<void> _completeCount() async {
    final entries=<Map<String,dynamic>>[];
    for(final m in _materials) {
      final raw=_countControllers[m['id'].toString()]?.text.trim()??'';
      final q=double.tryParse(raw.replaceAll('٬','').replaceAll('٫','.'));
      if(q==null||!q.isFinite||q<0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('مقدار شمارش «${m['name']}» معتبر نیست.')));
        return;
      }
      entries.add({'material_id':m['id'].toString(),'counted_quantity':q});
    }
    if(entries.isEmpty) return;
    final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('تأیید شمارش و تطبیق موجودی'),
      content:const Text('پس از تأیید، موجودی سیستم با مقادیر شمارش‌شده تطبیق داده می‌شود و تمام اختلاف‌ها در گردش انبار ثبت می‌شوند. این عملیات قابل برگشت خودکار نیست. ادامه می‌دهید؟'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('بازبینی')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تأیید و تطبیق'))],
    ));
    if(confirm!=true||!mounted) return;
    setState(()=>_saving=true);
    try {
      await _client.rpc('admin_complete_inventory_count',params:{
        'p_counts':entries,
        'p_notes':_notes.text.trim(),
      });
      _notes.clear();
      await _load();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('شمارش ثبت شد و موجودی سیستم با شمارش واقعی تطبیق یافت.')));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('ثبت شمارش ناموفق بود: $e'),backgroundColor:Theme.of(context).colorScheme.error));
    } finally { if(mounted) setState(()=>_saving=false); }
  }

  @override
  Widget build(BuildContext context) {
    if(_loading&&_materials.isEmpty) return const Center(child:CircularProgressIndicator());
    final visible=_showAll?_materials:_materials.where((m){
      final actual=double.tryParse(_countControllers[m['id'].toString()]?.text.trim()??'');
      return actual!=null&&(actual-_num(m['quantity_on_hand'])).abs()>0.0001;
    }).toList();
    return RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
      if(_error!=null) Text('خطا در دریافت اطلاعات: $_error',style:TextStyle(color:Theme.of(context).colorScheme.error)),
      Text('شمارش دوره‌ای انبار',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:6),
      const Text('موجودی واقعی هر ماده را وارد کنید. با ثبت نهایی، اختلاف به‌صورت گردش اصلاح موجودی ثبت می‌شود. همه مبالغ به تومان هستند.'),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        OutlinedButton.icon(onPressed:()=>setState(()=>_showAll=true),icon:const Icon(Icons.list_alt),label:const Text('همه مواد')),
        OutlinedButton.icon(onPressed:()=>setState(()=>_showAll=false),icon:const Icon(Icons.compare_arrows),label:const Text('فقط اختلاف‌ها')),
        OutlinedButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('بارگذاری مجدد')),
      ]),
      const SizedBox(height:12),
      if(_materials.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('ماده اولیه فعالی برای شمارش وجود ندارد.'))),
      ...visible.map((m) {
        final id=m['id'].toString();
        final system=_num(m['quantity_on_hand']);
        final actual=double.tryParse(_countControllers[id]?.text.trim()??'')??system;
        final diff=actual-system;
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(m['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15)),
          const SizedBox(height:6),
          Wrap(spacing:16,runSpacing:6,children:[
            Text('موجودی سیستم: ${_qty(system)} ${_unit(m['unit'])}'),
            Text('بهای واحد: ${_money(m['unit_cost'])} تومان'),
            Text('اختلاف: ${diff>0?'+':''}${_qty(diff)}',style:TextStyle(fontWeight:FontWeight.bold,color:diff==0?Colors.green:Theme.of(context).colorScheme.error)),
          ]),
          const SizedBox(height:8),
          TextFormField(
            controller:_countControllers[id],
            keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:InputDecoration(labelText:'موجودی واقعی (${_unit(m['unit'])})',border:const OutlineInputBorder(),suffixIcon:IconButton(tooltip:'کپی موجودی سیستم',onPressed:()=>setState(()=>_countControllers[id]!.text=_qty(system).replaceAll('٬','').replaceAll('٫','.')),icon:const Icon(Icons.copy_outlined))),
            onChanged:(_)=>setState((){}),
          ),
        ])));
      }),
      const SizedBox(height:8),
      TextField(controller:_notes,maxLines:2,decoration:const InputDecoration(labelText:'یادداشت شمارش (اختیاری)',border:OutlineInputBorder(),hintText:'مثلاً شمارش پایان ماه')),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:_saving||_materials.isEmpty?null:_completeCount,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.fact_check_outlined),label:Text(_saving?'در حال ثبت...':'ثبت شمارش و تطبیق موجودی')),
      const SizedBox(height:24),
      Text('سوابق شمارش',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      if(_history.isEmpty) const ListTile(title:Text('هنوز شمارش دوره‌ای ثبت نشده است.')),
      ..._history.map((h) {
        final lines=h['inventory_stock_count_items'] is List?(h['inventory_stock_count_items'] as List):const [];
        final number=h['count_number']??'—';
        return Card(child:ExpansionTile(
          leading:const Icon(Icons.history),
          title:Text('شمارش شماره ${_digits(number)} · ${_digits(h['count_date'])}'),
          subtitle:Text('${_digits(h['item_count']??0)} ماده · ${_digits(h['discrepancy_count']??0)} اختلاف · ارزش اختلاف: ${_money(h['total_discrepancy_cost'])} تومان'),
          children:[
            if((h['notes']??'').toString().isNotEmpty) ListTile(title:Text('یادداشت: ${h['notes']}')),
            ...lines.map<Widget>((raw){
              final line=Map<String,dynamic>.from(raw as Map);
              final rel=line['inventory_materials'] is Map?line['inventory_materials'] as Map:{};
              final delta=_num(line['difference_quantity']);
              return ListTile(
                title:Text('${rel['name']??'ماده اولیه'}'),
                subtitle:Text('سیستم: ${_qty(line['system_quantity'])} · واقعی: ${_qty(line['counted_quantity'])} · اختلاف: ${_qty(delta)} ${_unit(rel['unit'])}'),
                trailing:Text('${delta>0?'+':''}${_money(line['difference_cost'])} تومان',style:TextStyle(color:delta==0?Colors.green:Theme.of(context).colorScheme.error,fontWeight:FontWeight.w600)),
              );
            }),
          ],
        ));
      }),
    ]));
  }
}
