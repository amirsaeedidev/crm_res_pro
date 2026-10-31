import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const _categories = <String, String>{
    'personnel': 'حقوق و دستمزد',
    'rent': 'اجاره',
    'utilities': 'آب، برق و گاز',
    'delivery': 'ارسال و پیک',
    'marketing': 'بازاریابی',
    'maintenance': 'تعمیر و نگهداری',
    'ingredients_purchase': 'خرید مواد اولیه',
    'other': 'سایر',
  };
  static const _methods = <String, String>{
    'cash': 'نقدی',
    'card': 'کارت‌خوان',
    'bank_transfer': 'کارت به کارت / انتقال بانکی',
    'online': 'پرداخت آنلاین',
    'other': 'سایر',
  };

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _expenses = [];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SupabaseService.client
          .from('restaurant_expenses')
          .select('id,title,category,amount,occurred_on,notes,payment_method,reference_no,employee_name,receipt_path,created_at')
          .order('occurred_on', ascending: false)
          .order('created_at', ascending: false)
          .limit(250);
      if (mounted) {
        setState(() => _expenses =
            rows.map((row) => Map<String, dynamic>.from(row)).toList());
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'دریافت هزینه‌ها ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _digits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    final grouped = value.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '٬',
    );
    return '${_digits(grouped)} تومان';
  }

  num _parseMoney(String raw) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var normalized = raw;
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(persian[i], '$i');
      normalized = normalized.replaceAll(arabic[i], '$i');
    }
    normalized = normalized.replaceAll(RegExp(r'[,٬\s]'), '');
    return num.tryParse(normalized) ?? 0;
  }

  Future<void> _addExpense() async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    final reference = TextEditingController();
    final employee = TextEditingController();
    var category = 'other';
    var method = 'cash';
    var date = DateTime.now();
    PlatformFile? receipt;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ثبت هزینه جدید'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'عنوان هزینه *'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'عنوان هزینه را وارد کنید'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'مبلغ به تومان *',
                      suffixText: 'تومان',
                    ),
                    validator: (value) =>
                        _parseMoney(value ?? '') <= 0 ? 'مبلغ معتبر وارد کنید' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'دسته‌بندی هزینه'),
                    items: _categories.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => category = value ?? 'other'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: method,
                    decoration: const InputDecoration(labelText: 'روش پرداخت'),
                    items: _methods.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => method = value ?? 'cash'),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تاریخ هزینه'),
                    subtitle: Text('${_digits(date.year)}/${_digits(date.month.toString().padLeft(2, '0'))}/${_digits(date.day.toString().padLeft(2, '0'))}'),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                  ),
                  TextFormField(
                    controller: employee,
                    decoration: const InputDecoration(labelText: 'نام پرداخت‌کننده / کارمند (اختیاری)'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: reference,
                    decoration: const InputDecoration(labelText: 'شماره پیگیری (اختیاری)'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.pickFiles(
                        allowMultiple: false,
                        withData: true,
                        type: FileType.custom,
                        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
                      );
                      if (result == null || result.files.isEmpty) return;
                      final file = result.files.single;
                      final bytes = file.bytes;
                      if (bytes == null || bytes.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('خواندن فایل انتخاب‌شده ناموفق بود.')),
                        );
                        return;
                      }
                      if (bytes.length > 10 * 1024 * 1024) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('حداکثر حجم رسید ۱۰ مگابایت است.')),
                        );
                        return;
                      }
                      setDialogState(() => receipt = file);
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(receipt == null ? 'پیوست تصویر یا PDF رسید' : receipt!.name),
                  ),
                  if (receipt != null)
                    TextButton(
                      onPressed: () => setDialogState(() => receipt = null),
                      child: const Text('حذف فایل انتخاب‌شده'),
                    ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => _saving = true);
                      String? uploadedPath;
                      try {
                        if (receipt != null) {
                          final bytes = receipt!.bytes!;
                          final extension = receipt!.name.split('.').last.toLowerCase();
                          final contentType = switch (extension) {
                            'pdf' => 'application/pdf',
                            'png' => 'image/png',
                            'webp' => 'image/webp',
                            _ => 'image/jpeg',
                          };
                          uploadedPath = 'expenses/${const Uuid().v4()}.$extension';
                          await SupabaseService.storage
                              .from('expense-receipts')
                              .uploadBinary(
                                uploadedPath,
                                Uint8List.fromList(bytes),
                                fileOptions: FileOptions(
                                  contentType: contentType,
                                  upsert: false,
                                ),
                              );
                        }
                        await SupabaseService.client.from('restaurant_expenses').insert({
                          'title': title.text.trim(),
                          'amount': _parseMoney(amount.text),
                          'category': category,
                          'payment_method': method,
                          'occurred_on': date.toIso8601String().split('T').first,
                          'employee_name': employee.text.trim().isEmpty ? null : employee.text.trim(),
                          'reference_no': reference.text.trim().isEmpty ? null : reference.text.trim(),
                          'notes': notes.text.trim(),
                          'receipt_path': uploadedPath,
                          'created_by': SupabaseService.client.auth.currentUser?.id,
                        });
                        if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                      } catch (error) {
                        if (uploadedPath != null) {
                          try {
                            await SupabaseService.storage
                                .from('expense-receipts')
                                .remove([uploadedPath]);
                          } catch (_) {}
                        }
                        if (dialogContext.mounted) {
                          setDialogState(() => _saving = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('ثبت هزینه انجام نشد: $error')),
                          );
                        }
                      }
                    },
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('ثبت هزینه'),
            ),
          ],
        ),
      ),
    );
    _saving = false;
    if (mounted) setState(() {});
    title.dispose();
    amount.dispose();
    notes.dispose();
    reference.dispose();
    employee.dispose();
    if (saved == true && mounted) {
      await _loadExpenses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هزینه با موفقیت ثبت شد.')),
        );
      }
    }
  }

  Future<void> _openReceipt(String path) async {
    try {
      final url = await SupabaseService.storage
          .from('expense-receipts')
          .createSignedUrl(path, 60 * 5);
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('باز کردن رسید ممکن نشد.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('دریافت لینک امن رسید ناموفق بود: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<num>(
      0,
      (sum, row) => sum + (num.tryParse(row['amount']?.toString() ?? '') ?? 0),
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text('مدیریت هزینه‌ها'),
        actions: [
          IconButton(onPressed: _loadExpenses, icon: const Icon(Icons.refresh)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('ثبت هزینه'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
              title: const Text('مجموع هزینه‌های نمایش‌داده‌شده'),
              subtitle: const Text('حداکثر ۲۵۰ هزینه اخیر · مبالغ به تومان'),
              trailing: Text(_money(total), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Card(child: ListTile(
              title: Text(_error!),
              trailing: IconButton(onPressed: _loadExpenses, icon: const Icon(Icons.refresh)),
            )),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_expenses.isEmpty)
            const Expanded(child: Center(child: Text('هنوز هزینه‌ای ثبت نشده است.')))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadExpenses,
                child: ListView.separated(
                  itemCount: _expenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = _expenses[index];
                    final category = _categories[row['category']] ?? 'سایر';
                    final path = row['receipt_path']?.toString();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(
                          path == null ? Icons.receipt_long_outlined : Icons.attach_file,
                        )),
                        title: Text(row['title']?.toString() ?? 'هزینه بدون عنوان'),
                        subtitle: Text(
                          '$category · ${row['occurred_on'] ?? ''} · ${_methods[row['payment_method']] ?? 'سایر'}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_money(row['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (path != null && path.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _openReceipt(path),
                                icon: const Icon(Icons.open_in_new, size: 14),
                                label: const Text('مشاهده رسید'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
