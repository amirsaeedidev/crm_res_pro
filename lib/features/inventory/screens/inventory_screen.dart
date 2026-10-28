import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../repositories/inventory_repository.dart';
import 'inventory_import_manager.dart';
import 'supplier_purchase_manager.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  static const Map<String, String> _units = {
    'g': 'گرم',
    'kg': 'کیلوگرم',
    'ml': 'میلی‌لیتر',
    'l': 'لیتر',
    'unit': 'عدد',
    'pack': 'بسته',
    'box': 'جعبه',
  };

  late final InventoryRepository _repository;
  late final TabController _tabController;
  RealtimeChannel? _channel;

  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _transactions = [];

  bool _loading = false;
  bool _loadingAgain = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = InventoryRepository(client: SupabaseService.client);
    _tabController = TabController(length: 5, vsync: this);
    unawaited(_loadData());

    _channel = SupabaseService.client
        .channel('admin-inventory-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory_materials',
          callback: (_) => unawaited(_loadData()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_recipes',
          callback: (_) => unawaited(_loadData()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'inventory_transactions',
          callback: (_) => unawaited(_loadData()),
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    if (_loading) {
      _loadingAgain = true;
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _repository.getMaterials(),
        _repository.getProducts(),
        _repository.getRecipes(),
        _repository.getTransactions(),
      ]);

      if (!mounted) return;
      setState(() {
        _materials = results[0];
        _products = results[1];
        _recipes = results[2];
        _transactions = results[3];
      });
    } catch (error, stackTrace) {
      LoggerService.error(
        'Inventory screen refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = AppErrorMessage.from(error, fallback: 'دریافت اطلاعات انبار ناموفق بود. اتصال و سطح دسترسی را بررسی کنید.'));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
      if (mounted && _loadingAgain) {
        _loadingAgain = false;
        unawaited(_loadData());
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    final channel = _channel;
    if (channel != null) {
      unawaited(SupabaseService.client.removeChannel(channel));
    }
    super.dispose();
  }

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _formatDateTime(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return 'زمان نامشخص';
    final date = parsed.toLocal();
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
  }

  String _quantity(num value) => _persianDigits(
        value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 3)
            .replaceAll('.', '٫'),
      );

  String _money(num value) => _persianDigits(
        value.toStringAsFixed(0)
            .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '٬'),
      );

  String _unitLabel(dynamic unit) =>
      _units[unit?.toString()] ?? 'واحد نامشخص';

  num _number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;

  Map<String, dynamic>? _relation(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final safeMessage = AppErrorMessage.forDisplay(
      message,
      fallback: isError
          ? 'عملیات انبار ناموفق بود. اطلاعات و سطح دسترسی را بررسی کنید.'
          : 'عملیات با موفقیت انجام شد.',
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(safeMessage),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  String _errorMessage(Object error) => AppErrorMessage.forDisplay(
        error.toString(),
        fallback: 'عملیات انبار ناموفق بود. لطفاً دوباره تلاش کنید.',
      );

  Future<void> _editMaterial([Map<String, dynamic>? material]) async {
    final nameController = TextEditingController(
      text: (material?['name'] ?? '').toString(),
    );
    final skuController = TextEditingController(
      text: (material?['sku'] ?? '').toString(),
    );
    final costController = TextEditingController(
      text: (material?['unit_cost'] ?? 0).toString(),
    );
    final minimumController = TextEditingController(
      text: (material?['reorder_level'] ?? 0).toString(),
    );
    final notesController = TextEditingController(
      text: (material?['notes'] ?? '').toString(),
    );
    var selectedUnit = (material?['unit'] ?? 'g').toString();
    final formKey = GlobalKey<FormState>();

    final value =
        await showDialog<
          ({
            String name,
            String sku,
            String unit,
            double cost,
            double minimum,
            String notes,
          })
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
              title: Text(
                material == null ? 'ثبت ماده اولیه' : 'ویرایش ماده اولیه',
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'نام ماده اولیه *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value?.trim().isNotEmpty ?? false)
                              ? null
                              : 'نام را وارد کنید.',
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: skuController,
                          decoration: const InputDecoration(
                            labelText: 'کد انبار (اختیاری)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: selectedUnit,
                          decoration: const InputDecoration(
                            labelText: 'واحد اندازه‌گیری',
                            border: OutlineInputBorder(),
                          ),
                          items: _units.entries
                              .map(
                                (entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedUnit = value);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: costController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'هزینه واحد (تومان)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(
                              (value ?? '').trim(),
                            );
                            if (parsed == null ||
                                !parsed.isFinite ||
                                parsed < 0) {
                              return 'هزینه معتبر وارد کنید.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: minimumController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'حداقل موجودی برای هشدار',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(
                              (value ?? '').trim(),
                            );
                            if (parsed == null ||
                                !parsed.isFinite ||
                                parsed < 0) {
                              return 'حداقل موجودی معتبر وارد کنید.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'یادداشت',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('انصراف'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(dialogContext, (
                      name: nameController.text.trim(),
                      sku: skuController.text.trim(),
                      unit: selectedUnit,
                      cost: double.parse(costController.text.trim()),
                      minimum: double.parse(minimumController.text.trim()),
                      notes: notesController.text.trim(),
                    ));
                  },
                  child: const Text('ذخیره'),
                ),
              ],
            ),
          ),
        );

    nameController.dispose();
    skuController.dispose();
    costController.dispose();
    minimumController.dispose();
    notesController.dispose();

    if (value == null || !mounted) return;
    try {
      await _repository.saveMaterial(
        id: material?['id']?.toString(),
        name: value.name,
        sku: value.sku,
        unit: value.unit,
        unitCost: value.cost,
        reorderLevel: value.minimum,
        notes: value.notes,
      );
      await _loadData();
      _showMessage('ماده اولیه ذخیره شد.');
    } catch (error) {
      _showMessage(_errorMessage(error), isError: true);
    }
  }

  Future<void> _receiveStock(Map<String, dynamic> material) async {
    final quantityController = TextEditingController();
    final costController = TextEditingController(
      text: (material['unit_cost'] ?? 0).toString(),
    );
    final reasonController = TextEditingController(text: 'خرید / ورود موجودی');
    final formKey = GlobalKey<FormState>();

    final result =
        await showDialog<({double quantity, double cost, String reason})>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('ورود موجودی: ${material['name']}'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'مقدار خرید (${_unitLabel(material['unit'])})',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null || !parsed.isFinite || parsed <= 0) {
                          return 'مقدار باید بیشتر از صفر باشد.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'قیمت هر واحد (تومان)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null || !parsed.isFinite || parsed < 0) {
                          return 'قیمت معتبر وارد کنید.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: reasonController,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'شرح خرید',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.trim().isNotEmpty ?? false)
                          ? null
                          : 'شرح خرید الزامی است.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(dialogContext, (
                    quantity: double.parse(quantityController.text.trim()),
                    cost: double.parse(costController.text.trim()),
                    reason: reasonController.text.trim(),
                  ));
                },
                child: const Text('ثبت ورود'),
              ),
            ],
          ),
        );

    quantityController.dispose();
    costController.dispose();
    reasonController.dispose();
    if (result == null || !mounted) return;

    try {
      await _repository.receiveStock(
        materialId: material['id'].toString(),
        quantity: result.quantity,
        unitCost: result.cost,
        reason: result.reason,
      );
      await _loadData();
      _showMessage('ورود موجودی ثبت و میانگین بهای تمام‌شده به‌روزرسانی شد.');
    } catch (error) {
      _showMessage(_errorMessage(error), isError: true);
    }
  }

  Future<void> _adjustStock(Map<String, dynamic> material) async {
    final deltaController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<({double delta, String reason})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('اصلاح موجودی: ${material['name']}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'موجودی فعلی: ${_quantity(_number(material['quantity_on_hand']))} ${_unitLabel(material['unit'])}',
                ),
                TextFormField(
                  controller: deltaController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'تغییر مقدار؛ برای کاهش عدد منفی وارد کنید',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || !parsed.isFinite || parsed == 0) {
                      return 'تغییر مقدار نباید صفر باشد.';
                    }
                    if (_number(material['quantity_on_hand']) + parsed < 0) {
                      return 'موجودی نمی‌تواند منفی شود.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: reasonController,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'دلیل اصلاح',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.trim().isNotEmpty ?? false)
                      ? null
                      : 'دلیل الزامی است.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, (
                delta: double.parse(deltaController.text.trim()),
                reason: reasonController.text.trim(),
              ));
            },
            child: const Text('ثبت اصلاح'),
          ),
        ],
      ),
    );

    deltaController.dispose();
    reasonController.dispose();
    if (result == null || !mounted) return;

    try {
      await _repository.adjustStock(
        materialId: material['id'].toString(),
        quantityDelta: result.delta,
        reason: result.reason,
      );
      await _loadData();
      _showMessage('اصلاح موجودی در دفتر انبار ثبت شد.');
    } catch (error) {
      _showMessage(_errorMessage(error), isError: true);
    }
  }

  Future<void> _recordMovement(
    Map<String, dynamic> material,
    String movementType,
  ) async {
    final quantityController = TextEditingController();
    final isWaste = movementType == 'waste';
    final reasonController = TextEditingController(
      text: isWaste ? 'ثبت ضایعات' : 'ثبت مرجوعی به انبار',
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<({double quantity, String reason})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${isWaste ? 'ثبت ضایعات' : 'ثبت مرجوعی'}: ${material['name']}',
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'موجودی فعلی: ${_quantity(_number(material['quantity_on_hand']))} ${_unitLabel(material['unit'])}',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'مقدار ${isWaste ? 'ضایعات' : 'مرجوعی'}',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || !parsed.isFinite || parsed <= 0) {
                      return 'مقدار معتبر بزرگ‌تر از صفر وارد کنید.';
                    }
                    if (isWaste &&
                        parsed > _number(material['quantity_on_hand'])) {
                      return 'ضایعات از موجودی فعلی بیشتر است.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: reasonController,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'شرح و علت *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.trim().isNotEmpty ?? false)
                      ? null
                      : 'نوشتن علت الزامی است.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, (
                quantity: double.parse(quantityController.text.trim()),
                reason: reasonController.text.trim(),
              ));
            },
            child: const Text('ثبت گردش'),
          ),
        ],
      ),
    );

    quantityController.dispose();
    reasonController.dispose();
    if (result == null || !mounted) return;

    try {
      await _repository.recordMovement(
        materialId: material['id'].toString(),
        quantity: result.quantity,
        transactionType: movementType,
        reason: result.reason,
      );
      await _loadData();
      _showMessage(
        isWaste
            ? 'ضایعات از موجودی کسر و ثبت شد.'
            : 'مرجوعی به موجودی اضافه و ثبت شد.',
      );
    } catch (error) {
      _showMessage(_errorMessage(error), isError: true);
    }
  }

  Future<void> _editRecipe([Map<String, dynamic>? recipe]) async {
    if (_products.isEmpty || _materials.isEmpty) {
      _showMessage('ابتدا حداقل یک غذا و یک ماده اولیه ثبت کنید.');
      return;
    }

    var productId = (recipe?['product_id'] ?? _products.first['id']).toString();
    var materialId = (recipe?['material_id'] ?? _materials.first['id'])
        .toString();
    if (!_products.any((item) => item['id'].toString() == productId)) {
      if (recipe != null) {
        _showMessage(
          'غذای مرتبط با این دستور غیرفعال است؛ ابتدا آن را در بخش محصولات فعال کنید.',
          isError: true,
        );
        return;
      }
      productId = _products.first['id'].toString();
    }
    if (!_materials.any((item) => item['id'].toString() == materialId)) {
      materialId = _materials.first['id'].toString();
    }

    final quantityController = TextEditingController(
      text: (recipe?['quantity_per_product'] ?? '1').toString(),
    );
    final notesController = TextEditingController(
      text: (recipe?['notes'] ?? '').toString(),
    );
    final formKey = GlobalKey<FormState>();

    final value =
        await showDialog<
          ({String productId, String materialId, double quantity, String notes})
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
              title: Text(
                recipe == null ? 'دستور مصرف غذا' : 'ویرایش دستور مصرف',
              ),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: productId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'غذا / محصول',
                          border: OutlineInputBorder(),
                        ),
                        items: _products
                            .map(
                              (product) => DropdownMenuItem<String>(
                                value: product['id'].toString(),
                                child: Text(
                                  product['name'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => productId = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: materialId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'ماده اولیه',
                          border: OutlineInputBorder(),
                        ),
                        items: _materials
                            .map(
                              (material) => DropdownMenuItem<String>(
                                value: material['id'].toString(),
                                child: Tooltip(
                                  message:
                                      'موجودی فعلی: '
                                      '${_quantity(_number(material['quantity_on_hand']))} '
                                      '${_unitLabel(material['unit'])}\n'
                                      'بهای واحد: ${_money(_number(material['unit_cost']))} تومان\n'
                                      'حد هشدار: ${_quantity(_number(material['reorder_level']))}',
                                  child: Text(
                                    '${material['name']} (${_unitLabel(material['unit'])})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => materialId = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'مقدار مصرف برای یک غذا',
                          border: OutlineInputBorder(),
                          helperText:
                              'واحد آن همان واحد ماده اولیه انتخاب‌شده است.',
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null ||
                              !parsed.isFinite ||
                              parsed <= 0) {
                            return 'مقدار معتبر بزرگ‌تر از صفر وارد کنید.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: notesController,
                        minLines: 1,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'یادداشت دستور مصرف',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'این مقدار هنگام انتقال سفارش به «در حال آماده‌سازی» از انبار کم می‌شود.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('انصراف'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(dialogContext, (
                      productId: productId,
                      materialId: materialId,
                      quantity: double.parse(quantityController.text.trim()),
                      notes: notesController.text.trim(),
                    ));
                  },
                  child: const Text('ذخیره دستور'),
                ),
              ],
            ),
          ),
        );

    quantityController.dispose();
    notesController.dispose();
    if (value == null || !mounted) return;

    try {
      await _repository.saveRecipe(
        id: recipe?['id']?.toString(),
        productId: value.productId,
        materialId: value.materialId,
        quantity: value.quantity,
        notes: value.notes,
      );
      await _loadData();
      _showMessage('دستور مصرف ذخیره شد.');
    } catch (error) {
      _showMessage(_errorMessage(error), isError: true);
    }
  }

  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف دستور مصرف؟'),
        content: const Text(
          'حذف دستور روی مصرف‌های ثبت‌شده قبلی اثر نمی‌گذارد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _repository.deleteRecipe(recipe['id'].toString());
      await _loadData();
      _showMessage('دستور مصرف حذف شد.');
    } catch (error) {
      _showMessage(_errorMessage(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مدیریت انبارداری',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'مواد اولیه، بهای تمام‌شده، دستور مصرف غذا و گردش انبار',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'همگام‌سازی',
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: Text(
              'دریافت اطلاعات انبار ناموفق بود: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_loading && _materials.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.inventory_2_outlined),
                      text: 'مواد اولیه',
                    ),
                    Tab(
                      icon: Icon(Icons.restaurant_menu),
                      text: 'دستور مصرف غذا',
                    ),
                    Tab(icon: Icon(Icons.history), text: 'گردش انبار'),
                    Tab(icon: Icon(Icons.upload_file_outlined), text: 'ایمپورت اکسل'),
                    Tab(icon: Icon(Icons.local_shipping_outlined), text: 'تامین‌کنندگان و خرید'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMaterialsTab(),
                      _buildRecipesTab(),
                      _buildTransactionsTab(),
                      const InventoryImportManager(),
                      const SupplierPurchaseManager(),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMaterialsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            children: [
              Text(
                'مواد اولیه (${_materials.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _editMaterial(),
                icon: const Icon(Icons.add),
                label: const Text('افزودن ماده'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _materials.isEmpty
              ? const Center(child: Text('هنوز ماده اولیه‌ای ثبت نشده است.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _materials.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final material = _materials[index];
                    final stock = _number(material['quantity_on_hand']);
                    final minimum = _number(material['reorder_level']);
                    final unit = _unitLabel(material['unit']);
                    final unitCost = _number(material['unit_cost']);
                    final lowStock = stock <= minimum;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  lowStock
                                      ? Icons.warning_amber_rounded
                                      : Icons.inventory_2_outlined,
                                  color: lowStock
                                      ? Colors.orange
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        material['name'].toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'کد: ${material['sku'] ?? '—'} · $unit',
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'عملیات انبار',
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      unawaited(_editMaterial(material));
                                    } else if (action == 'receive') {
                                      unawaited(_receiveStock(material));
                                    } else if (action == 'adjust') {
                                      unawaited(_adjustStock(material));
                                    } else if (action == 'waste') {
                                      unawaited(
                                        _recordMovement(material, 'waste'),
                                      );
                                    } else if (action == 'return') {
                                      unawaited(
                                        _recordMovement(material, 'return'),
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'receive',
                                      child: Text('ورود / خرید موجودی'),
                                    ),
                                    PopupMenuItem(
                                      value: 'adjust',
                                      child: Text('اصلاح موجودی'),
                                    ),
                                    PopupMenuItem(
                                      value: 'waste',
                                      child: Text('ثبت ضایعات'),
                                    ),
                                    PopupMenuItem(
                                      value: 'return',
                                      child: Text('ثبت مرجوعی'),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('ویرایش ماده'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 14,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'موجودی: ${_quantity(stock)} $unit',
                                  style: TextStyle(
                                    color: lowStock ? Colors.orange : null,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('بهای واحد: ${_money(unitCost)} تومان'),
                                Text(
                                  'ارزش موجودی: ${_money(stock * unitCost)} تومان',
                                ),
                                Text('حد هشدار: ${_quantity(minimum)} $unit'),
                              ],
                            ),
                            if (lowStock)
                              const Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'موجودی به حد هشدار رسیده است.',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            if ((material['notes'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  material['notes'].toString(),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecipesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'دستورهای مصرف (${_recipes.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editRecipe(),
                icon: const Icon(Icons.add),
                label: const Text('دستور جدید'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _recipes.isEmpty
              ? const Center(child: Text('هنوز دستور مصرفی تعریف نشده است.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _recipes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final recipe = _recipes[index];
                    final product = _relation(recipe['products']);
                    final material = _relation(recipe['inventory_materials']);
                    final quantity = _number(recipe['quantity_per_product']);
                    final cost = _number(material?['unit_cost']);
                    final unit = _unitLabel(material?['unit']);
                    final notes = (recipe['notes'] ?? '').toString();

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.restaurant_menu),
                        title: Text(
                          '${product?['name'] ?? 'غذای حذف‌شده'} ← ${material?['name'] ?? 'ماده حذف‌شده'}',
                        ),
                        subtitle: Text(
                          'مصرف هر غذا: ${_quantity(quantity)} $unit · '
                          'هزینه تخمینی: ${_money(quantity * cost)} تومان'
                          '${notes.isEmpty ? '' : '\n$notes'}',
                        ),
                        isThreeLine: notes.isNotEmpty,
                        trailing: PopupMenuButton<String>(
                          tooltip: 'مدیریت دستور',
                          onSelected: (action) {
                            if (action == 'edit') {
                              unawaited(_editRecipe(recipe));
                            } else if (action == 'delete') {
                              unawaited(_deleteRecipe(recipe));
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'راهنما: با تغییر وضعیت سفارش به «در حال آماده‌سازی»، میزان مصرف مواد اولیه بر اساس تعداد غذا محاسبه و به‌صورت اتمیک از موجودی کم می‌شود.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsTab() {
    if (_transactions.isEmpty) {
      return const Center(child: Text('گردش انبار هنوز ثبت نشده است.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _transactions.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final transaction = _transactions[index];
        final material = _relation(transaction['inventory_materials']);
        final delta = _number(transaction['quantity_delta']);
        final type = switch (transaction['transaction_type']) {
          'purchase' => 'ورود / خرید',
          'adjustment' => 'اصلاح دستی',
          'order_usage' => 'مصرف سفارش',
          'waste' => 'ضایعات',
          'return' => 'مرجوعی',
          _ => transaction['transaction_type'].toString(),
        };
        final unit = _unitLabel(material?['unit']);
        final orderId = transaction['order_id'];
        final createdAt = _formatDateTime(transaction['created_at']);
        final reason = transaction['reason'] ?? '';

        return ListTile(
          leading: Icon(
            delta < 0 ? Icons.south_west : Icons.north_east,
            color: delta < 0 ? Colors.red : Colors.green,
          ),
          title: Text('${material?['name'] ?? 'ماده'} · $type'),
          subtitle: Text(
            '$reason\n$createdAt${orderId == null ? '' : '\nسفارش: $orderId'}',
          ),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${delta > 0 ? '+' : ''}${_quantity(delta)} $unit',
                style: TextStyle(
                  color: delta < 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_money(_number(transaction['total_cost']))} ت',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
