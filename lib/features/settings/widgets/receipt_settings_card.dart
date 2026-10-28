import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_card.dart';

class ReceiptSettingsCard extends StatefulWidget {
  const ReceiptSettingsCard({super.key});

  @override
  State<ReceiptSettingsCard> createState() => _ReceiptSettingsCardState();
}

class _ReceiptSettingsCardState extends State<ReceiptSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  final _storeName = TextEditingController();
  final _logoUrl = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _header = TextEditingController();
  final _footer = TextEditingController();
  String _paperSize = 'a4';
  bool _showLogo = true;
  bool _showDate = true;
  bool _showCustomer = true;
  bool _showPhone = true;
  bool _showOrderType = true;
  bool _showTable = true;
  bool _showQueue = true;
  bool _showDiscount = true;
  bool _showNotes = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _storeName.dispose();
    _logoUrl.dispose();
    _phone.dispose();
    _address.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService.client
          .from('receipt_settings')
          .select('*')
          .eq('id', 'main')
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        _storeName.text = (row['store_name'] ?? '').toString();
        _logoUrl.text = (row['logo_url'] ?? '').toString();
        _phone.text = (row['store_phone'] ?? '').toString();
        _address.text = (row['store_address'] ?? '').toString();
        _header.text = (row['header_text'] ?? '').toString();
        _footer.text = (row['footer_text'] ?? '').toString();
        _paperSize = (row['paper_size'] ?? 'a4').toString();
        _showLogo = row['show_logo'] == true;
        _showDate = row['show_date'] != false;
        _showCustomer = row['show_customer'] != false;
        _showPhone = row['show_phone'] != false;
        _showOrderType = row['show_order_type'] != false;
        _showTable = row['show_table_number'] != false;
        _showQueue = row['show_queue_number'] != false;
        _showDiscount = row['show_discount'] != false;
        _showNotes = row['show_notes'] != false;
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = 'بارگذاری تنظیمات فاکتور ناموفق بود: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _error = 'بارگذاری تنظیمات فاکتور ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final logo = _logoUrl.text.trim();
      if (logo.isNotEmpty) {
        final uri = Uri.tryParse(logo);
        if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
          throw const FormatException('نشانی لوگو باید با http یا https شروع شود.');
        }
      }
      await SupabaseService.client.from('receipt_settings').upsert({
        'id': 'main',
        'store_name': _storeName.text.trim(),
        'logo_url': logo,
        'store_phone': _phone.text.trim(),
        'store_address': _address.text.trim(),
        'header_text': _header.text.trim(),
        'footer_text': _footer.text.trim(),
        'paper_size': _paperSize,
        'show_logo': _showLogo,
        'show_date': _showDate,
        'show_customer': _showCustomer,
        'show_phone': _showPhone,
        'show_order_type': _showOrderType,
        'show_table_number': _showTable,
        'show_queue_number': _showQueue,
        'show_discount': _showDiscount,
        'show_notes': _showNotes,
        'updated_by': SupabaseService.client.auth.currentUser?.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات فاکتور ذخیره شد.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1, TextInputType? keyboardType}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSizes.sm),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: identical(controller, _storeName) ? (value) => (value?.trim().isNotEmpty ?? false) ? null : 'نام فروشگاه الزامی است.' : null,
    ),
  );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    return AppCard(child: Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تنظیمات فاکتور و چاپ رسید', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('نام فروشگاه، لوگو، شماره سفارش، نوبت روز، تخفیف، اقلام و اندازه چاپ PDF از این قسمت مدیریت می‌شوند.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSizes.md),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Wrap(spacing: AppSizes.md, runSpacing: AppSizes.sm, children: [
          SizedBox(width: 320, child: _field(_storeName, 'نام فروشگاه *')),
          SizedBox(width: 320, child: _field(_logoUrl, 'آدرس عمومی لوگو (URL)')),
          SizedBox(width: 320, child: _field(_phone, 'تلفن فروشگاه', keyboardType: TextInputType.phone)),
          SizedBox(width: 320, child: _field(_address, 'آدرس فروشگاه')),
          SizedBox(width: 320, child: _field(_header, 'متن سربرگ فاکتور')),
          SizedBox(width: 320, child: _field(_footer, 'متن پایین فاکتور')),
        ]),
        const SizedBox(height: AppSizes.sm),
        SizedBox(width: 320, child: DropdownButtonFormField<String>(
          initialValue: _paperSize,
          decoration: const InputDecoration(labelText: 'اندازه چاپ', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'a4', child: Text('A4 (برگه معمولی)')),
            DropdownMenuItem(value: 'roll_80', child: Text('رول حرارتی ۸۰ میلی‌متر')),
            DropdownMenuItem(value: 'roll_58', child: Text('رول حرارتی ۵۸ میلی‌متر')),
          ],
          onChanged: (value) { if (value != null) setState(() => _paperSize = value); },
        )),
        const Divider(height: AppSizes.lg),
        Text('نمایش در فاکتور', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Wrap(spacing: 24, runSpacing: 0, children: [
          SizedBox(width: 260, child: _toggle('لوگو', _showLogo, (v) => setState(() => _showLogo = v))),
          SizedBox(width: 260, child: _toggle('تاریخ و ساعت', _showDate, (v) => setState(() => _showDate = v))),
          SizedBox(width: 260, child: _toggle('نام مشتری', _showCustomer, (v) => setState(() => _showCustomer = v))),
          SizedBox(width: 260, child: _toggle('شماره تماس مشتری', _showPhone, (v) => setState(() => _showPhone = v))),
          SizedBox(width: 260, child: _toggle('نوع سفارش', _showOrderType, (v) => setState(() => _showOrderType = v))),
          SizedBox(width: 260, child: _toggle('شماره میز', _showTable, (v) => setState(() => _showTable = v))),
          SizedBox(width: 260, child: _toggle('شماره نوبت روز', _showQueue, (v) => setState(() => _showQueue = v))),
          SizedBox(width: 260, child: _toggle('مبلغ و کد تخفیف', _showDiscount, (v) => setState(() => _showDiscount = v))),
          SizedBox(width: 260, child: _toggle('یادداشت سفارش', _showNotes, (v) => setState(() => _showNotes = v))),
        ]),
        const SizedBox(height: AppSizes.md),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: const Text('ذخیره تنظیمات فاکتور'),
        )),
      ]),
    ));
  }
}
