import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';

class InventoryMaterialReportManager extends StatefulWidget {
  const InventoryMaterialReportManager({super.key});
  @override
  State<InventoryMaterialReportManager> createState()=>_InventoryMaterialReportManagerState();
}
class _InventoryMaterialReportManagerState extends State<InventoryMaterialReportManager>{
  final _client=SupabaseService.client;
  DateTimeRange _range=DateTimeRange(start:DateTime.now().subtract(const Duration(days:30)),end:DateTime.now());
  bool _loading=true;
  String? _error;
  List<Map<String,dynamic>> _rows=[];
  @override void initState(){super.initState();unawaited(_load());}
  Future<void> _load() async {
    setState(()=>_loading=true); 
    try {
      final raw=await _client.rpc('get_inventory_material_activity_report',params:{
        'p_start_date':DateTime(_range.start.year,_range.start.month,_range.start.day).toUtc().toIso8601String(),
        'p_end_date':DateTime(_range.end.year,_range.end.month,_range.end.day,23,59,59).toUtc().toIso8601String(),
      });
      final data=Map<String,dynamic>.from(raw as Map);
      final chart=(data['chart_data'] as List? ?? const []);
      if(mounted)setState(()=>_rows=chart.map((e)=>Map<String,dynamic>.from(e as Map)).toList());
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  String _digits(Object? v){var s=v?.toString()??'0';const a='0123456789',p='۰۱۲۳۴۵۶۷۸۹';for(var i=0;i<10;i++){s=s.replaceAll(a[i],p[i]);}return s;}
  num _n(dynamic v)=>v is num?v:num.tryParse('$v')??0;
  String _qty(dynamic v) => _digits(_n(v).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), ''));
  String _money(dynamic v)=>_digits(_n(v).toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>'٬'));
  String _unit(dynamic v)=>({'g':'گرم','kg':'کیلوگرم','ml':'میلی‌لیتر','l':'لیتر','unit':'عدد','pack':'بسته','box':'جعبه'}[v?.toString()]??v?.toString()??'واحد');
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:8,runSpacing:8,alignment:WrapAlignment.start,children:[
      OutlinedButton.icon(onPressed:()async{final r=await showDateRangePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime.now(),initialDateRange:_range,helpText:'انتخاب بازه گزارش');if(r!=null){setState(()=>_range=r);unawaited(_load());}},icon:const Icon(Icons.date_range),label:Text('${_digits(_range.start.toIso8601String().substring(0,10))} تا ${_digits(_range.end.toIso8601String().substring(0,10))}')),
      FilledButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('به‌روزرسانی')),
    ])),
    if(_loading) const LinearProgressIndicator(minHeight:2),
    if(_error!=null) Padding(padding:const EdgeInsets.all(12),child:Text('گزارش بارگذاری نشد: $_error',style:TextStyle(color:Theme.of(context).colorScheme.error))),
    Expanded(child:_rows.isEmpty && !_loading ? const Center(child:Text('در این بازه اطلاعاتی وجود ندارد.')) : ListView.separated(
      padding:const EdgeInsets.all(12),itemCount:_rows.length,
      separatorBuilder:(_, _) =>const SizedBox(height:8),
      itemBuilder:(context,index){final r=_rows[index];final unit=_unit(r['stock_unit']);
        Widget metric(String label,String value)=>Expanded(child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:.35),borderRadius:BorderRadius.circular(10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:Theme.of(context).textTheme.labelSmall),const SizedBox(height:4),Text(value,style:const TextStyle(fontWeight:FontWeight.w700))])));
        return Card(child:ExpansionTile(
          title:Text('${r['material_name']??'ماده اولیه'}',style:const TextStyle(fontWeight:FontWeight.w700)),
          subtitle:Text('موجودی فعلی: ${_qty(r['current_stock'])} $unit · ارزش موجودی: ${_money(r['current_stock_value'])} تومان'),
          children:[Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Column(children:[
            Row(children:[metric('خرید در بازه','${_qty(r['purchased_quantity'])} $unit'),const SizedBox(width:8),metric('هزینه خرید','${_money(r['purchase_cost'])} تومان')]),
            const SizedBox(height:8),
            Row(children:[metric('مصرف','${_qty(r['consumed_quantity'])} $unit'),const SizedBox(width:8),metric('بهای مصرف','${_money(r['consumption_cost'])} تومان')]),
            const SizedBox(height:8),
            Row(children:[metric('ضایعات','${_qty(r['waste_quantity'])} $unit'),const SizedBox(width:8),metric('هزینه ضایعات','${_money(r['waste_cost'])} تومان')]),
            const SizedBox(height:8),
            Row(children:[metric('مرجوعی','${_qty(r['return_quantity'])} $unit'),const SizedBox(width:8),metric('بهای واحد فعلی','${_money(r['unit_cost'])} تومان / $unit')]),
          ]))],
        ));
      },
    )),
  ]);
}
),''));
  String _money(dynamic v)=>_digits(_n(v).toStringAsFixed(0).replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'),(_)=>'٬'));
  String _unit(dynamic v)=>({'g':'گرم','kg':'کیلوگرم','ml':'میلی‌لیتر','l':'لیتر','unit':'عدد','pack':'بسته','box':'جعبه'}[v?.toString()]??v?.toString()??'واحد');
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:8,runSpacing:8,alignment:WrapAlignment.start,children:[
      OutlinedButton.icon(onPressed:()async{final r=await showDateRangePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime.now(),initialDateRange:_range,helpText:'انتخاب بازه گزارش');if(r!=null){setState(()=>_range=r);unawaited(_load());}},icon:const Icon(Icons.date_range),label:Text('${_digits(_range.start.toIso8601String().substring(0,10))} تا ${_digits(_range.end.toIso8601String().substring(0,10))}')),
      FilledButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('به‌روزرسانی')),
    ])),
    if(_loading) const LinearProgressIndicator(minHeight:2),
    if(_error!=null) Padding(padding:const EdgeInsets.all(12),child:Text('گزارش بارگذاری نشد: $_error',style:TextStyle(color:Theme.of(context).colorScheme.error))),
    Expanded(child:_rows.isEmpty && !_loading ? const Center(child:Text('در این بازه اطلاعاتی وجود ندارد.')) : ListView.separated(
      padding:const EdgeInsets.all(12),itemCount:_rows.length,
      separatorBuilder:(_, _) =>const SizedBox(height:8),
      itemBuilder:(context,index){final r=_rows[index];final unit=_unit(r['stock_unit']);
        Widget metric(String label,String value)=>Expanded(child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:.35),borderRadius:BorderRadius.circular(10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:Theme.of(context).textTheme.labelSmall),const SizedBox(height:4),Text(value,style:const TextStyle(fontWeight:FontWeight.w700))])));
        return Card(child:ExpansionTile(
          title:Text('${r['material_name']??'ماده اولیه'}',style:const TextStyle(fontWeight:FontWeight.w700)),
          subtitle:Text('موجودی فعلی: ${_qty(r['current_stock'])} $unit · ارزش موجودی: ${_money(r['current_stock_value'])} تومان'),
          children:[Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Column(children:[
            Row(children:[metric('خرید در بازه','${_qty(r['purchased_quantity'])} $unit'),const SizedBox(width:8),metric('هزینه خرید','${_money(r['purchase_cost'])} تومان')]),
            const SizedBox(height:8),
            Row(children:[metric('مصرف','${_qty(r['consumed_quantity'])} $unit'),const SizedBox(width:8),metric('بهای مصرف','${_money(r['consumption_cost'])} تومان')]),
            const SizedBox(height:8),
            Row(children:[metric('ضایعات','${_qty(r['waste_quantity'])} $unit'),const SizedBox(width:8),metric('هزینه ضایعات','${_money(r['waste_cost'])} تومان')]),
            const SizedBox(height:8),
            Row(children:[metric('مرجوعی','${_qty(r['return_quantity'])} $unit'),const SizedBox(width:8),metric('بهای واحد فعلی','${_money(r['unit_cost'])} تومان / $unit')]),
          ]))],
        ));
      },
    )),
  ]);
}
