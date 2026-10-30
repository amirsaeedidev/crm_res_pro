import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';
import '../utils/inventory_unit_converter.dart';

class SupplierPurchaseManager extends StatefulWidget {
  const SupplierPurchaseManager({super.key});
  @override
  State<SupplierPurchaseManager> createState() => _SupplierPurchaseManagerState();
}

class _SupplierPurchaseManagerState extends State<SupplierPurchaseManager> {
  final _client = SupabaseService.client;
  bool _loading = true;
  List<Map<String,dynamic>> _suppliers = [];
  List<Map<String,dynamic>> _materials = [];
  List<Map<String,dynamic>> _purchases = [];
  List<Map<String,dynamic>> _items = [];
  String? _error;

  @override
  void initState() { super.initState(); unawaited(_load()); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _client.from('inventory_suppliers').select('*').order('name').limit(300),
        _client.from('inventory_materials').select('id,name,unit,unit_cost,quantity_on_hand').order('name').limit(300),
        _client.from('inventory_purchases').select('id,purchase_number,supplier_id,invoice_number,purchase_date,total_amount,paid_amount,payment_status,notes,created_at,inventory_suppliers(name)').order('created_at', ascending: false).limit(100),
        _client.from('inventory_purchase_items').select('id,purchase_id,material_id,quantity,unit_cost,line_total,entered_quantity,entered_unit,conversion_factor,entered_unit_cost,inventory_materials(name,unit)').order('created_at', ascending: false).limit(500),
      ]);
      if (!mounted) return;
      setState(() {
        _suppliers = (results[0] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
        _materials = (results[1] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
        _purchases = (results[2] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
        _items = (results[3] as List).map((e)=>Map<String,dynamic>.from(e)).toList();
      });
    } catch(e) { if(mounted) setState(()=>_error=e.toString()); }
    finally { if(mounted) setState(()=>_loading=false); }
  }


  List<String> _compatibleUnits(String stockUnit) =>
      ['g', 'kg', 'ml', 'l', 'unit', 'pack', 'box']
          .where((unit) => InventoryUnitConverter.areCompatible(unit, stockUnit))
          .toList(growable: false);

  String _unitName(String unit) => const {
    'g': 'گرم', 'kg': 'کیلوگرم', 'ml': 'میلی‌لیتر', 'l': 'لیتر',
    'unit': 'عدد', 'pack': 'بسته', 'box': 'جعبه',
  }[unit] ?? unit;

  String _paymentStatusName(Object? status) => switch (status?.toString()) {
    'paid' => 'تسویه‌شده',
    'partial' => 'پرداخت ناقص',
    _ => 'پرداخت‌نشده',
  };

  void _message(String text, {bool error=false}) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
  }

  Future<void> _supplierDialog([Map<String,dynamic>? supplier]) async {
    final name=TextEditingController(text:'${supplier?['name'] ?? ''}');
    final contact=TextEditingController(text:'${supplier?['contact_name'] ?? ''}');
    final phone=TextEditingController(text:'${supplier?['phone'] ?? ''}');
    final email=TextEditingController(text:'${supplier?['email'] ?? ''}');
    final address=TextEditingController(text:'${supplier?['address'] ?? ''}');
    final notes=TextEditingController(text:'${supplier?['notes'] ?? ''}');
    final key=GlobalKey<FormState>();
    final save=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(supplier==null?'ثبت تامین‌کننده':'ویرایش تامین‌کننده'),
      content:SizedBox(width:480,child:SingleChildScrollView(child:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:name,decoration:const InputDecoration(labelText:'نام تامین‌کننده *'),validator:(v)=>(v?.trim().isNotEmpty??false)?null:'نام الزامی است'),
        TextFormField(controller:contact,decoration:const InputDecoration(labelText:'نام رابط')),
        TextFormField(controller:phone,decoration:const InputDecoration(labelText:'تلفن'),keyboardType:TextInputType.phone),
        TextFormField(controller:email,decoration:const InputDecoration(labelText:'ایمیل'),keyboardType:TextInputType.emailAddress),
        TextFormField(controller:address,decoration:const InputDecoration(labelText:'آدرس')),
        TextFormField(controller:notes,decoration:const InputDecoration(labelText:'یادداشت'),maxLines:2),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),FilledButton(onPressed:(){if(key.currentState!.validate()) Navigator.pop(ctx,true);},child:const Text('ذخیره'))],
    ));
    if(save==true && mounted) {
      try {
        final payload={'name':name.text.trim(),'contact_name':contact.text.trim(),'phone':phone.text.trim(),'email':email.text.trim(),'address':address.text.trim(),'notes':notes.text.trim(),'updated_at':DateTime.now().toUtc().toIso8601String()};
        if(supplier==null) { await _client.from('inventory_suppliers').insert(payload); }
        else { await _client.from('inventory_suppliers').update(payload).eq('id',supplier['id']); }
        await _load(); _message('اطلاعات تامین‌کننده ذخیره شد.');
      } catch(e) { _message('ذخیره تامین‌کننده ناموفق بود: $e',error:true); }
    }
    for(final c in [name,contact,phone,email,address,notes]) { c.dispose(); }
  }

  Future<void> _purchaseDialog() async {
    if(_suppliers.where((s)=>s['is_active']==true).isEmpty || _materials.isEmpty) {
      _message('ابتدا یک تامین‌کننده فعال و حداقل یک ماده اولیه ثبت کنید.',error:true); return;
    }
    String supplierId=_suppliers.firstWhere((s)=>s['is_active']==true)['id'].toString();
    final invoice=TextEditingController();
    final discount=TextEditingController(text:'0');
    final shipping=TextEditingController(text:'0');
    final paid=TextEditingController(text:'0');
    final notes=TextEditingController();
    final lines=<Map<String,dynamic>>[];
    final key=GlobalKey<FormState>();
    final result=await showDialog<Map<String,dynamic>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:const Text('ثبت خرید مواد اولیه'),
      content:SizedBox(width:620,child:SingleChildScrollView(child:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(initialValue:supplierId,isExpanded:true,decoration:const InputDecoration(labelText:'تأمین‌کننده'),items:_suppliers.where((s)=>s['is_active']==true).map((s)=>DropdownMenuItem(value:s['id'].toString(),child:Text(s['name'].toString()))).toList(),onChanged:(v){if(v!=null)setDialog(()=>supplierId=v);}),
        TextFormField(controller:invoice,decoration:const InputDecoration(labelText:'شماره فاکتور')),
        const SizedBox(height:12),
        ...lines.asMap().entries.map((entry) {
          final i=entry.key; final line=entry.value;
          final material=_materials.firstWhere((m)=>m['id'].toString()==line['material_id']);
          final compatibleUnits = _compatibleUnits(material['unit'].toString());
                    return Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
            Row(children:[Expanded(child:Text(material['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold))),IconButton(onPressed:()=>setDialog(()=>lines.removeAt(i)),icon:const Icon(Icons.delete_outline))]),
            Row(children:[
              Expanded(child:TextFormField(initialValue:line['quantity'].toString(),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'مقدار خرید'),onChanged:(v)=>line['quantity']=InventoryUnitConverter.parseLocalizedNumber(v)??0)),
              const SizedBox(width:8),
              Expanded(child:TextFormField(key:ValueKey('purchase-price-$i-${line['purchase_unit']}'),initialValue:line['unit_cost'].toString(),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'بهای هر واحد (تومان)'),onChanged:(v)=>line['unit_cost']=InventoryUnitConverter.parseLocalizedNumber(v)??-1)),
            ]),
            const SizedBox(height:8),
            DropdownButtonFormField<String>(
              key: ValueKey('purchase-unit-${material['id']}-${line['purchase_unit']}'),
              initialValue: compatibleUnits.contains(line['purchase_unit']) ? line['purchase_unit'] as String : material['unit'].toString(),
              decoration: InputDecoration(labelText: 'واحد خرید (موجودی انبار به ${_unitName(material['unit'].toString())} ثبت می‌شود)'),
              items: compatibleUnits.map((unit) => DropdownMenuItem<String>(value: unit, child: Text(_unitName(unit)))).toList(),
              onChanged: (unit) {
                if (unit == null) return;
                setDialog(() {
                  final oldUnit = (line['purchase_unit'] ?? material['unit']).toString();
                  final ratio = InventoryUnitConverter.quantityRatio(purchaseUnit: unit, stockUnit: material['unit'].toString());
                  final oldRatio = InventoryUnitConverter.quantityRatio(purchaseUnit: oldUnit, stockUnit: material['unit'].toString());
                  line['unit_cost'] = ((line['unit_cost'] as num).toDouble() * oldRatio / ratio);
                  line['purchase_unit'] = unit;
                });
              },
            ),
          ])));
        }),
        Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:(){
          final available=_materials.where((m)=>!lines.any((l)=>l['material_id']==m['id'].toString())).toList();
          if(available.isEmpty){_message('همه مواد اولیه به فاکتور اضافه شده‌اند.');return;}
          setDialog(()=>lines.add({'material_id':available.first['id'].toString(),'quantity':1.0,'unit_cost':double.tryParse('${available.first['unit_cost']}')??0.0,'purchase_unit':available.first['unit'].toString()}));
        },icon:const Icon(Icons.add),label:const Text('افزودن ماده اولیه'))),
        TextFormField(controller:discount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'تخفیف فاکتور (تومان)')),
        TextFormField(controller:shipping,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'هزینه حمل (تومان)')),
        TextFormField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'مبلغ پرداخت‌شده (تومان)')),
        TextFormField(controller:notes,decoration:const InputDecoration(labelText:'یادداشت'),maxLines:2),
        const SizedBox(height:8),
        Text('جمع اقلام: ${_money(_itemsSubtotal(lines))} تومان',style:const TextStyle(fontWeight:FontWeight.bold)),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('انصراف')),FilledButton(onPressed:(){
        if(lines.isEmpty || lines.any((l)=>(l['quantity'] as num)<=0 || (l['unit_cost'] as num)<0)){_message('حداقل یک قلم با مقدار مثبت و بهای معتبر اضافه کنید.',error:true);return;}
        final d=InventoryUnitConverter.parseLocalizedNumber(discount.text)??0, sh=InventoryUnitConverter.parseLocalizedNumber(shipping.text)??0, p=InventoryUnitConverter.parseLocalizedNumber(paid.text)??0;
        final total=lines.fold<double>(0,(sum,l)=>sum+((l['quantity'] as num)*(l['unit_cost'] as num)))-d+sh;
        if(d<0||sh<0||p<0||p>total){_message('تخفیف، حمل یا مبلغ پرداختی معتبر نیست.',error:true);return;}
        Navigator.pop(ctx,{'supplier_id':supplierId,'invoice_number':invoice.text.trim(),'discount':d,'shipping':sh,'paid':p,'notes':notes.text.trim(),'items':lines.map((l)=>Map<String,dynamic>.from(l)).toList()});
      },child:const Text('ثبت خرید و ورود موجودی'))],
    )));
    if(result!=null && mounted) {
      try {
        await _client.rpc('admin_record_inventory_purchase',params:{
          'p_supplier_id':result['supplier_id'],'p_invoice_number':result['invoice_number'],
          'p_purchase_date':DateTime.now().toIso8601String().substring(0,10),
          'p_items':(result['items'] as List).map((item) { final copy=Map<String,dynamic>.from(item); copy['purchase_unit'] ??= _materials.firstWhere((m)=>m['id'].toString()==copy['material_id'])['unit']; return copy; }).toList(),'p_discount_amount':result['discount'],'p_shipping_amount':result['shipping'],
          'p_paid_amount':result['paid'],'p_notes':result['notes'],
        });
        await _load(); _message('خرید ثبت شد؛ موجودی و بهای تمام‌شده به‌روزرسانی شد.');
      } catch(e) { _message('ثبت خرید ناموفق بود: $e',error:true); }
    }
    for(final c in [invoice,discount,shipping,paid,notes]) { c.dispose(); }
  }

  double _itemsSubtotal(List<Map<String, dynamic>> lines) => lines.fold<double>(0, (sum, line) => sum + ((line['quantity'] as num) * (line['unit_cost'] as num)));

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    final formatted = n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '٬',
    );
    return _fa(formatted);
  }

  String _fa(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if(_loading) return const Center(child:CircularProgressIndicator());
    return RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(12),children:[
      if(_error!=null) Text('بارگذاری اطلاعات ناموفق بود: $_error',style:TextStyle(color:Theme.of(context).colorScheme.error)),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton.icon(onPressed:_purchaseDialog,icon:const Icon(Icons.add_shopping_cart),label:const Text('ثبت خرید')),
        OutlinedButton.icon(onPressed:()=>_supplierDialog(),icon:const Icon(Icons.person_add_alt_1),label:const Text('افزودن تامین‌کننده')),
        OutlinedButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('بروزرسانی')),
      ]),
      const SizedBox(height:16),
      Text('تامین‌کنندگان (${_fa(_suppliers.length)})',style:Theme.of(context).textTheme.titleLarge),
      if(_suppliers.isEmpty) const ListTile(title:Text('تامین‌کننده‌ای ثبت نشده است.')),
      ..._suppliers.map((s)=>Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.storefront_outlined)),
        title:Text(s['name'].toString()),
        subtitle:Text(['${s['contact_name']??''}','${s['phone']??''}','${s['email']??''}'].where((x)=>x.trim().isNotEmpty).join(' · ')),
        trailing:IconButton(tooltip:'ویرایش',onPressed:()=>_supplierDialog(s),icon:const Icon(Icons.edit_outlined)),
      ))),
      const SizedBox(height:16),
      Text('سوابق خرید (${_fa(_purchases.length)})',style:Theme.of(context).textTheme.titleLarge),
      if(_purchases.isEmpty) const ListTile(title:Text('هنوز خریدی ثبت نشده است.')),
      ..._purchases.map((p) {
        final supplier=p['inventory_suppliers'] is Map ? (p['inventory_suppliers'] as Map)['name']?.toString()??'تامین‌کننده' : 'تامین‌کننده';
        final items=_items.where((i)=>i['purchase_id'].toString()==p['id'].toString()).toList();
        final itemText=items.map((i) {
          final rel = i['inventory_materials'];
          final name = rel is Map ? rel['name'] ?? 'ماده اولیه' : 'ماده اولیه';
          final quantity = i['entered_quantity'] ?? i['quantity'];
          final unit = (i['entered_unit'] ?? (rel is Map ? rel['unit'] : null) ?? '').toString();
          final enteredQuantity = i['entered_quantity'];
          final lineTotal = i['line_total'] is num ? (i['line_total'] as num).toDouble() : 0.0;
          final unitCost = enteredQuantity is num && enteredQuantity > 0
              ? lineTotal / enteredQuantity
              : (i['unit_cost'] as num? ?? 0);
          final hasInvoiceUnitCost = i['entered_unit_cost'] is num;
          final displayedUnitCost = hasInvoiceUnitCost ? i['entered_unit_cost'] as num : unitCost;
          final unitCostLabel = hasInvoiceUnitCost ? 'بهای واحد فاکتور' : 'بهای واحد ثبت‌شده';
          return '$name: $quantity ${_unitName(unit)} × ${_money(displayedUnitCost)} تومان ($unitCostLabel) · بهای تمام‌شده اقلام: ${_money(lineTotal)} تومان';
        }).join('، ');
        return Card(child:ExpansionTile(
          leading:const Icon(Icons.receipt_long_outlined),
          title:Text('فاکتور ${p['invoice_number'].toString().isEmpty?'شماره ${_fa(p['purchase_number'])}':'${p['invoice_number']}'} · ${_money(p['total_amount'])} تومان'),
          subtitle:Text('$supplier · ${_fa(p['purchase_date'])} · ${_paymentStatusName(p['payment_status'])}'),
          children:[Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(itemText.isEmpty?'اقلام خرید در دسترس نیستند':itemText),
            if((p['notes']??'').toString().isNotEmpty) Text('یادداشت: ${p['notes']}'),
            Text('پرداخت‌شده: ${_money(p['paid_amount'])} تومان'),
          ]))],
        ));
      }),
    ]));
  }
}
