import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../repositories/inventory_repository.dart';

class InventoryImportManager extends StatefulWidget {
  const InventoryImportManager({super.key});

  @override
  State<InventoryImportManager> createState() => _InventoryImportManagerState();
}

class _InventoryImportManagerState extends State<InventoryImportManager> {
  final _client = SupabaseService.client;
  late final InventoryRepository _repository = InventoryRepository(client: _client);
  String _type = 'materials';
  bool _busy = false;
  List<Map<String, dynamic>> _batches = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadBatches());
  }

  Future<void> _loadBatches() async {
    try {
      final rows = await _client.from('inventory_import_batches')
          .select('*').order('created_at', ascending: false).limit(100);
      if (mounted) setState(() => _batches = rows.map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (e) {
      if (mounted) _message('دریافت سوابق فایل‌ها ناموفق بود: $e', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  String _cell(List<Data?> row, int index) =>
      index < row.length ? (row[index]?.value?.toString().trim() ?? '') : '';

  double? _number(String value) {
    final normalized = value.replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.');
    final result = double.tryParse(normalized);
    return result != null && result.isFinite ? result : null;
  }

  Future<void> _downloadTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    if (_type == 'materials') {
      sheet.appendRow([
        TextCellValue('name'), TextCellValue('sku'), TextCellValue('unit'),
        TextCellValue('unit_cost'), TextCellValue('reorder_level'),
        TextCellValue('initial_stock'), TextCellValue('notes'),
      ]);
      sheet.appendRow([
        TextCellValue('آرد'), TextCellValue('MAT-001'), TextCellValue('kg'),
        IntCellValue(50000), IntCellValue(5), IntCellValue(10),
        TextCellValue('نمونه؛ قبل از ایمپورت حذف کنید'),
      ]);
    } else {
      sheet.appendRow([
        TextCellValue('product_name'), TextCellValue('material_name'),
        TextCellValue('quantity_per_product'), TextCellValue('notes'),
      ]);
      sheet.appendRow([
        TextCellValue('پیتزا مخصوص'), TextCellValue('آرد'),
        DoubleCellValue(0.25), TextCellValue('نمونه؛ قبل از ایمپورت حذف کنید'),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      _message('ساخت قالب اکسل ناموفق بود.', error: true);
      return;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'ذخیره قالب اکسل',
      fileName: _type == 'materials' ? 'inventory_materials_template.xlsx' : 'food_recipes_template.xlsx',
      bytes: Uint8List.fromList(bytes),
    );
    if (path != null && mounted) _message('قالب اکسل آماده شد.');
  }

  Future<bool> _previewBeforeImport(List<String> headers, List<List<Data?>> rows) async {
    final nonEmpty = rows.where((r) => r.any((cell) => (cell?.value?.toString().trim() ?? '').isNotEmpty)).toList();
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('پیش‌نمایش فایل اکسل'),
      content: SizedBox(width: 760, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('نوع داده: ${_type == 'materials' ? 'مواد اولیه' : 'دستور مصرف غذا'} · تعداد ردیف‌ها: ${nonEmpty.length}'),
        const SizedBox(height: 8),
        const Text('مقادیر و ستون‌های الزامی بررسی اولیه شده‌اند؛ اعتبارسنجی هر ردیف هنگام پردازش نیز انجام می‌شود.'),
        const SizedBox(height: 8),
        Flexible(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SingleChildScrollView(child: DataTable(
          columns: [const DataColumn(label: Text('ردیف')), ...headers.map((h) => DataColumn(label: Text(h)))],
          rows: nonEmpty.take(100).toList().asMap().entries.map((entry) => DataRow(cells: [
            DataCell(Text('${entry.key + 2}')),
            ...headers.asMap().entries.map((h) => DataCell(SizedBox(width: 120, child: Text(h.key < entry.value.length ? (entry.value[h.key]?.value?.toString() ?? '') : '', maxLines: 2, overflow: TextOverflow.ellipsis))))
          ])).toList(),
        )))),
        if (nonEmpty.length > 100) const Text('فقط ۱۰۰ ردیف اول در پیش‌نمایش دیده می‌شود.'),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید و ادامه ایمپورت')),
      ],
    )) ?? false;
  }
  Future<void> _pickAndImport() async {
    if (_busy) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _message('محتوای فایل قابل خواندن نیست.', error: true);
      return;
    }
    if (file.size > 15 * 1024 * 1024) {
      _message('حداکثر حجم فایل ۱۵ مگابایت است.', error: true);
      return;
    }

    setState(() => _busy = true);
    String? storagePath;
    String? batchId;
    var success = 0;
    var failed = 0;
    final errors = <String>[];
    try {
      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) throw Exception('فایل هیچ شیتی ندارد.');
      final sheet = workbook.tables.values.first;
      if (sheet.rows.length < 2) throw Exception('فایل فقط سرستون دارد یا خالی است.');
      final headers = sheet.rows.first.map((c) => (c?.value?.toString() ?? '').trim().toLowerCase()).toList();
      int col(String name) => headers.indexOf(name);
      final required = _type == 'materials'
          ? ['name', 'unit', 'unit_cost', 'reorder_level']
          : ['product_name', 'material_name', 'quantity_per_product'];
      final missing = required.where((h) => col(h) < 0).toList();
      if (missing.isNotEmpty) throw Exception('ستون‌های الزامی وجود ندارند: ${missing.join(', ')}');

      final dataRows = sheet.rows.skip(1).where((row) => row.any((cell) => (cell?.value?.toString().trim() ?? '').isNotEmpty)).toList();
      final previewOk = await _previewBeforeImport(headers, dataRows);
      if (!previewOk) { if (mounted) setState(() => _busy = false); return; }
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('برای ایمپورت باید وارد حساب مدیر شده باشید.');
      storagePath = '$userId/${DateTime.now().toUtc().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
      await _client.storage.from('inventory-imports').uploadBinary(
        storagePath, bytes,
        fileOptions: const FileOptions(upsert: false, contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      );
      final batch = await _client.from('inventory_import_batches').insert({
        'file_name': file.name,
        'storage_path': storagePath,
        'import_type': _type,
        'status': 'completed',
        'created_by': userId,
      }).select('id').single();
      batchId = batch['id'].toString();

      final materials = await _repository.getMaterials();
      final products = await _repository.getProducts();
      final materialByName = {for (final m in materials) (m['name'] ?? '').toString().trim().toLowerCase(): m};
      final productByName = {for (final p in products) (p['name'] ?? '').toString().trim().toLowerCase(): p};
      final knownUnits = {'g', 'kg', 'ml', 'l', 'unit', 'pack', 'box'};
      for (var i = 0; i < dataRows.length; i++) {
        final row = dataRows[i];
        try {
          if (_type == 'materials') {
            final name = _cell(row, col('name'));
            final skuRaw = col('sku') < 0 ? '' : _cell(row, col('sku'));
            final unit = _cell(row, col('unit')).toLowerCase();
            final cost = _number(_cell(row, col('unit_cost')));
            final reorder = _number(_cell(row, col('reorder_level')));
            final initial = col('initial_stock') < 0 || _cell(row, col('initial_stock')).isEmpty
                ? 0.0 : _number(_cell(row, col('initial_stock')));
            final notes = col('notes') < 0 ? '' : _cell(row, col('notes'));
            if (name.isEmpty || !knownUnits.contains(unit) || cost == null || cost < 0 || reorder == null || reorder < 0 || initial == null || initial < 0) {
              throw Exception('نام، واحد یا مقادیر عددی معتبر نیستند.');
            }
            final skuMatches = skuRaw.isEmpty ? <Map<String, dynamic>>[] : materials.where((m) => (m['sku'] ?? '').toString().toLowerCase() == skuRaw.toLowerCase()).toList();
            final existing = skuRaw.isNotEmpty
                ? (skuMatches.isEmpty ? null : skuMatches.first)
                : materialByName[name.toLowerCase()];
            await _repository.saveMaterial(
              id: existing?['id']?.toString(),
              name: name, sku: skuRaw.isEmpty ? null : skuRaw, unit: unit,
              unitCost: cost, reorderLevel: reorder, notes: notes,
            );
            if (existing == null && initial > 0) {
              final saved = await _client.from('inventory_materials').select('id').eq('name', name).maybeSingle();
              if (saved != null) {
                await _repository.receiveStock(
                  materialId: saved['id'].toString(), quantity: initial,
                  unitCost: cost, reason: 'موجودی اولیه از فایل ${file.name}',
                );
              }
            }
          } else {
            final productName = _cell(row, col('product_name'));
            final materialName = _cell(row, col('material_name'));
            final quantity = _number(_cell(row, col('quantity_per_product')));
            final notes = col('notes') < 0 ? '' : _cell(row, col('notes'));
            final product = productByName[productName.toLowerCase()];
            final material = materialByName[materialName.toLowerCase()];
            if (product == null || material == null || quantity == null || quantity <= 0) {
              throw Exception('غذا/ماده اولیه پیدا نشد یا مقدار مصرف معتبر نیست.');
            }
            await _repository.saveRecipe(
              productId: product['id'].toString(),
              materialId: material['id'].toString(),
              quantity: quantity,
              notes: notes,
            );
          }
          success++;
        } catch (e) {
          failed++;
          if (errors.length < 8) errors.add('ردیف ${i + 2}: $e');
        }
      }

      final status = failed == 0 ? 'completed' : (success == 0 ? 'failed' : 'partial');
      await _client.from('inventory_import_batches').update({
        'status': status,
        'rows_total': success + failed,
        'rows_success': success,
        'rows_failed': failed,
        'error_summary': errors.join('\n'),
      }).eq('id', batchId);
      await _loadBatches();
      if (mounted) {
        _message('ایمپورت تمام شد؛ موفق: $success، ناموفق: $failed${errors.isEmpty ? '' : '\n' + errors.join('\n')}', error: failed > 0);
      }
    } catch (e) {
      if (batchId != null) {
        try {
          await _client.from('inventory_import_batches').update({
            'status': 'failed', 'rows_total': success + failed,
            'rows_success': success, 'rows_failed': failed + 1, 'error_summary': e.toString(),
          }).eq('id', batchId);
        } catch (_) {}
      }
      if (storagePath != null && batchId == null) {
        try { await _client.storage.from('inventory-imports').remove([storagePath]); } catch (_) {}
      }
      _message('ایمپورت انجام نشد: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadArchivedFile(Map<String, dynamic> batch) async {
    try {
      final path = batch['storage_path']?.toString() ?? '';
      if (path.isEmpty) throw Exception('مسیر فایل آرشیو موجود نیست.');
      final bytes = await _client.storage.from('inventory-imports').download(path);
      await FilePicker.saveFile(dialogTitle: 'ذخیره مجدد فایل آرشیو', fileName: (batch['file_name'] ?? 'inventory_import.xlsx').toString(), bytes: bytes);
      if (mounted) _message('درخواست ذخیره فایل آرشیو انجام شد.');
    } catch (e) { _message('دانلود فایل آرشیو ناموفق بود: $e', error: true); }
  }

  Future<void> _showBatchDetails(Map<String, dynamic> batch) async {
    final summary = (batch['error_summary'] ?? '').toString().trim();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('جزئیات ایمپورت: ${batch['file_name'] ?? 'فایل اکسل'}'),
      content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('کل ردیف‌ها: ${batch['rows_total'] ?? 0}'),
        Text('موفق: ${batch['rows_success'] ?? 0}'),
        Text('ناموفق: ${batch['rows_failed'] ?? 0}'),
        const Divider(),
        Text(summary.isEmpty ? 'خطایی برای این فایل ثبت نشده است.' : summary),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
    ));
  }
  Future<void> _deleteBatch(Map<String, dynamic> batch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف فایل آرشیو؟'),
        content: Text('فایل «${batch['file_name']}» و سابقه ایمپورت آن حذف می‌شود. داده‌های واردشده از انبار حذف نخواهند شد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف فایل')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final path = batch['storage_path']?.toString();
      if (path != null && path.isNotEmpty) {
        await _client.storage.from('inventory-imports').remove([path]);
      }
      await _client.from('inventory_import_batches').delete().eq('id', batch['id']);
      await _loadBatches();
      _message('فایل آرشیو حذف شد. داده‌های ثبت‌شده تغییری نکردند.');
    } catch (e) {
      _message('حذف فایل ناموفق بود: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ورود اطلاعات از اکسل', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('فایل‌ها به‌صورت خصوصی در Supabase نگهداری می‌شوند. قبل از ثبت، سرستون‌ها و مقادیر اعتبارسنجی می‌شوند.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'نوع فایل', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'materials', child: Text('مواد اولیه و موجودی اولیه')),
                  DropdownMenuItem(value: 'recipes', child: Text('دستور مصرف غذاها')),
                ],
                onChanged: _busy ? null : (value) { if (value != null) setState(() => _type = value); },
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pickAndImport,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
                  label: Text(_busy ? 'در حال پردازش…' : 'انتخاب و ایمپورت اکسل'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _downloadTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('دریافت قالب اکسل'),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                _type == 'materials'
                    ? 'ستون‌ها: name، unit، unit_cost، reorder_level؛ اختیاری: sku، initial_stock، notes. واحدها: g، kg، ml، l، unit، pack، box. مقدار موجودی فقط برای ماده جدید ثبت می‌شود تا ایمپورت مجدد موجودی را دوباره افزایش ندهد.'
                    : 'ستون‌ها: product_name، material_name، quantity_per_product؛ اختیاری: notes. نام غذا و ماده باید با اطلاعات موجود در سیستم مطابقت داشته باشد.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('فایل‌های ایمپورت‌شده', style: Theme.of(context).textTheme.titleLarge)),
          IconButton(onPressed: _loadBatches, tooltip: 'تازه‌سازی', icon: const Icon(Icons.refresh)),
        ]),
        if (_batches.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('هنوز فایلی ثبت نشده است.')))
        else
          ..._batches.map((batch) {
            final status = switch (batch['status']) {
              'completed' => 'موفق',
              'partial' => 'نیمه‌موفق',
              'failed' => 'ناموفق',
              _ => 'در حال پردازش',
            };
            final date = DateTime.tryParse(batch['created_at']?.toString() ?? '')?.toLocal();
            final details = '${batch['import_type'] == 'materials' ? 'مواد اولیه' : 'دستور غذا'} · $status · موفق ${batch['rows_success'] ?? 0} / ناموفق ${batch['rows_failed'] ?? 0} · ${date == null ? '' : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}'}';
            return Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text((batch['file_name'] ?? 'فایل اکسل').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(details),
                trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'دانلود مجدد فایل', onPressed: () => _downloadArchivedFile(batch), icon: const Icon(Icons.download_outlined)),
                  IconButton(tooltip: 'مشاهده جزئیات خطاها', onPressed: () => _showBatchDetails(batch), icon: const Icon(Icons.info_outline)),
                  IconButton(tooltip: 'حذف فایل و سابقه', onPressed: () => _deleteBatch(batch), icon: const Icon(Icons.delete_outline, color: Colors.red)),
                ]),
              ),
            );
          }),
      ],
    );
  }
}
