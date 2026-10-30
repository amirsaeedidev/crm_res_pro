import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';
class LoyaltyRulesManager extends StatefulWidget {
 const LoyaltyRulesManager({super.key});
 @override State<LoyaltyRulesManager> createState()=>_LoyaltyRulesManagerState();
}
class _LoyaltyRulesManagerState extends State<LoyaltyRulesManager>{
 final _client=SupabaseService.client;
 final _earnAmount=TextEditingController(text:'100000'),_earnPoints=TextEditingController(text:'1'),_pointValue=TextEditingController(text:'1000'),_minimum=TextEditingController(text:'10'),_maxPercent=TextEditingController(text:'30'),_expiryDays=TextEditingController(text:'365');
 bool _enabled=true,_loading=true,_saving=false;
 @override void initState(){super.initState();_load();}
 @override void dispose(){for(final c in [_earnAmount,_earnPoints,_pointValue,_minimum,_maxPercent,_expiryDays]){c.dispose();}super.dispose();}
 Future<void> _load() async {try{final row=await _client.from('loyalty_program_settings').select().eq('id',true).maybeSingle();if(row!=null&&mounted){setState((){
 _enabled=row['is_enabled']==true;_earnAmount.text='\${row['earn_amount_toman']}';_earnPoints.text='\${row['earn_points']}';_pointValue.text='\${row['point_value_toman']}';_minimum.text='\${row['minimum_redeem_points']}';_maxPercent.text='\${row['maximum_discount_percent']}';_expiryDays.text='\${row['expiry_days']}';
 });}}catch(e){if(mounted)_notify('بارگذاری قوانین وفاداری ناموفق بود: $e',true);}finally{if(mounted)setState(()=>_loading=false);}}
 void _notify(String m,[bool error=false])=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(m),backgroundColor:error?Theme.of(context).colorScheme.error:null));
 int? _int(TextEditingController c)=>int.tryParse(c.text.trim()); double? _double(TextEditingController c)=>double.tryParse(c.text.trim());
 Future<void> _save() async {final earn=_int(_earnAmount),points=_int(_earnPoints),value=_int(_pointValue),min=_int(_minimum),cap=_double(_maxPercent),days=_int(_expiryDays);
 if(earn==null||points==null||value==null||min==null||cap==null||days==null||earn<=0||points<=0||value<=0||min<=0||cap<1||cap>100||days<1||days>3650){_notify('مقادیر قوانین معتبر نیستند.',true);return;}
 setState(()=>_saving=true);try{await _client.rpc('admin_update_loyalty_rules',params:{'p_is_enabled':_enabled,'p_earn_amount_toman':earn,'p_earn_points':points,'p_point_value_toman':value,'p_minimum_redeem_points':min,'p_maximum_discount_percent':cap,'p_expiry_days':days});_notify('قوانین باشگاه مشتریان ذخیره شد.');}catch(e){_notify('ذخیره قوانین ناموفق بود: $e',true);}finally{if(mounted)setState(()=>_saving=false);}}
 Future<void> _expire() async {final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('اجرای انقضای امتیازها'),content:const Text('امتیازهای کسب‌شده‌ای که تاریخ انقضایشان گذشته، از موجودی کیف امتیاز کسر و در گردش امتیاز ثبت می‌شوند. ادامه می‌دهید؟'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('اجرای انقضا'))]));if(ok!=true)return;try{final n=await _client.rpc('admin_expire_loyalty_points');_notify('تعداد $n امتیاز منقضی شد.');}catch(e){_notify('اجرای انقضا ناموفق بود: $e',true);}}
 Widget _field(String label,TextEditingController c,{String suffix=''})=>TextFormField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:label,suffixText:suffix,border:const OutlineInputBorder()));
 @override Widget build(BuildContext context){if(_loading)return const Card(child:Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator()));return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Row(children:[const Icon(Icons.loyalty_outlined),const SizedBox(width:8),Expanded(child:Text('قوانین باشگاه مشتریان',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold))),Switch(value:_enabled,onChanged:(v)=>setState(()=>_enabled=v))]),
 Text('تنظیم نحوه کسب، ارزش، انقضا و تبدیل امتیاز به تخفیف. همه مبالغ به تومان هستند.',style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:12),
 LayoutBuilder(builder:(context,box){final width=box.maxWidth;final columns=width>700?3:width>420?2:1;return GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:columns,childAspectRatio:width>420?3.5:4.2,crossAxisSpacing:10,mainAxisSpacing:10,children:[
 _field('به‌ازای هر مبلغ خرید',_earnAmount,suffix:'تومان'),_field('امتیاز کسب‌شده',_earnPoints,suffix:'امتیاز'),_field('ارزش هر امتیاز',_pointValue,suffix:'تومان'),_field('حداقل امتیاز قابل تبدیل',_minimum,suffix:'امتیاز'),_field('سقف تخفیف سفارش',_maxPercent,suffix:'درصد'),_field('مدت اعتبار امتیاز',_expiryDays,suffix:'روز')]);}),
 const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.save_outlined),label:Text(_saving?'در حال ذخیره':'ذخیره قوانین')),OutlinedButton.icon(onPressed:_expire,icon:const Icon(Icons.hourglass_disabled),label:const Text('اجرای انقضای امتیازها'))]),
 const SizedBox(height:6),const Text('اجرای انقضا در این نسخه دستی است. تبدیل امتیاز در پنل فقط مبلغ تخفیف را محاسبه می‌کند؛ کسر قطعی امتیاز باید هنگام ثبت سفارش در اپ مشتریان به‌صورت اتمیک متصل شود.',style:TextStyle(fontSize:11,color:Colors.grey))
 ])));}
}