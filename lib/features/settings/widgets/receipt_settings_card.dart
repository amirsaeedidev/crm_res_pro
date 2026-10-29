import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/utils/app_error_message.dart';

class ReceiptSettingsCard extends StatefulWidget {
  const ReceiptSettingsCard({super.key});

  @override
  State<ReceiptSettingsCard> createState() => _ReceiptSettingsCardState();
}

class _ReceiptSettingsCardState extends State<ReceiptSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  final _storeName = TextEditingController();
  final _logoUrl = TextEditingController();
  final _imagePicker = ImagePicker();
  String? _pendingOldLogoUrl;
  bool _logoBusy = false;
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
      if (mounted) setState(() => _error = AppErrorMessage.from(e, fallback: 'بارگذاری تنظیمات فاکتور انجام نشد. دوباره تلاش کنید.'));
    } catch (e) {
      if (mounted) setState(() => _error = AppErrorMessage.from(e, fallback: 'بارگذاری تنظیمات فاکتور انجام نشد. اتصال و سطح دسترسی را بررسی کنید.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  String? _logoStoragePath(String url) {
    const marker = '/storage/v1/object/public/receipt-logos/';
    final index = url.indexOf(marker);
    if (index < 0) return null;
    return Uri.decodeComponent(url.substring(index + marker.length).split('?').first);
  }

  Future<void> _pickLogo() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1200);
      if (file == null || !mounted) return;
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
      if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
        throw const FormatException('فرمت لوگو باید JPG، PNG یا WebP باشد.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('حجم لوگو باید کمتر از ۲ مگابایت باشد.');
      }
      setState(() { _logoBusy = true; _error = null; });
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) throw const FormatException('برای تغییر لوگو ابتدا وارد حساب مدیر شوید.');
      final safeExt = ext == 'jpeg' ? 'jpg' : ext;
      final path = '$userId/receipt-logo.$safeExt';
      final contentType = safeExt == 'png' ? 'image/png' : safeExt == 'webp' ? 'image/webp' : 'image/jpeg';
      await SupabaseService.client.storage.from('receipt-logos').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType, cacheControl: '3600'),
      );
      final oldUrl = _logoUrl.text.trim();
      final newUrl = SupabaseService.client.storage.from('receipt-logos').getPublicUrl(path);
      if (!mounted) return;
      setState(() {
        if (oldUrl.isNotEmpty && oldUrl != newUrl) _pendingOldLogoUrl = oldUrl;
        _logoUrl.text = newUrl;
        _showLogo = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = AppErrorMessage.from(e, fallback: 'بارگذاری لوگو انجام نشد. دسترسی Storage را بررسی کنید.'));
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  void _removeLogo() {
    final oldUrl = _logoUrl.text.trim();
    setState(() {
      if (oldUrl.isNotEmpty) _pendingOldLogoUrl = oldUrl;
      _logoUrl.clear();
      _showLogo = false;
      _error = null;
    });
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
          throw const FormatException('نشانی اینترنتی لوگو معتبر نیست.');
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
      final oldPath = _pendingOldLogoUrl == null ? null : _logoStoragePath(_pendingOldLogoUrl!);
      final newPath = _logoStoragePath(logo);
      if (oldPath != null && oldPath != newPath) {
        try {
          await SupabaseService.client.storage.from('receipt-logos').remove([oldPath]);
        } catch (_) {
          // Settings are saved; an inaccessible old object can be cleaned up later.
        }
      }
      _pendingOldLogoUrl = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات فاکتور ذخیره شد.')));
    } catch (e) {
      if (mounted) setState(() => _error = AppErrorMessage.from(e, fallback: 'ذخیره تنظیمات فاکتور انجام نشد. اطلاعات و سطح دسترسی را بررسی کنید.'));
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
        Text('نام فروشگاه، لوگو، شماره سفارش، نوبت روز، تخفیف، اقلام و اندازه چاپ برگه از این قسمت مدیریت می‌شوند.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSizes.md),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Wrap(spacing: AppSizes.md, runSpacing: AppSizes.sm, children: [
          SizedBox(width: 320, child: _field(_storeName, 'نام فروشگاه *')),
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('لوگوی فاکتور', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 72, height: 72, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _logoUrl.text.trim().isEmpty
                            ? const Icon(Icons.restaurant, size: 30)
                            : Image.network(
                                _logoUrl.text.trim(), width: 68, height: 68, fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_logoUrl.text.trim().isEmpty ? 'لوگویی انتخاب نشده' : 'لوگوی فعلی'),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _logoBusy || _saving ? null : _pickLogo,
                                  icon: _logoBusy
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.upload_outlined),
                                  label: Text(_logoUrl.text.trim().isEmpty ? 'انتخاب تصویر' : 'تغییر تصویر'),
                                ),
                                if (_logoUrl.text.trim().isNotEmpty)
                                  TextButton.icon(
                                    onPressed: _logoBusy || _saving ? null : _removeLogo,
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('حذف'),
                                  ),
                              ],
                            ),
                            const Text('JPG، PNG یا WebP؛ حداکثر ۲ مگابایت', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
            DropdownMenuItem(value: 'a4', child: Text('برگه استاندارد')),
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
          onPressed: _loading || _saving || _logoBusy ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: const Text('ذخیره تنظیمات فاکتور'),
        )),
      ]),
    ));
  }
}
