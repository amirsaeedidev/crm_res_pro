import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import '../../../core/utils/app_error_message.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_textfield.dart';
import '../../../models/discount_model.dart';
import '../../../models/user_model.dart';
import '../../../repositories/customers_repository.dart';
import '../../../providers/discounts_provider.dart';
import '../../../repositories/discounts_repository.dart';

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var digits = newValue.text.replaceAll(',', '').replaceAll('٬', '');
    digits = digits.replaceAllMapped(RegExp(r'[^0-9۰-۹٠-٩]'), (m) {
      final char = m.group(0)!;
      final p = persian.indexOf(char);
      final a = arabic.indexOf(char);
      return (p >= 0 ? p : a >= 0 ? a : int.tryParse(char) ?? '').toString();
    });
    final formatted = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class DiscountFormScreen extends StatefulWidget {
  final String? discountId;

  const DiscountFormScreen({super.key, this.discountId});

  @override
  State<DiscountFormScreen> createState() => _DiscountFormScreenState();
}

class _DiscountFormScreenState extends State<DiscountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _codeController = TextEditingController();
  final _valueController = TextEditingController();
  final _minPurchaseController = TextEditingController();
  final _maxDiscountController = TextEditingController();
  final _totalUsageController = TextEditingController();
  final _perUserUsageController = TextEditingController();
  final _targetPhonesController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final Map<String, UserModel> _selectedCustomers = {};
  List<UserModel> _customerSuggestions = [];
  Timer? _customerSearchDebounce;
  bool _customerSearchLoading = false;
  int _customerSearchRequest = 0;
  
  final _moneyFormatter = _ThousandsSeparatorInputFormatter();

  String? _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isActive = true;
  bool _restrictedToCustomers = false;
  final Set<String> _deliveryChannels = {'notification'};
  bool _isLoading = false;

  bool get isEditing => widget.discountId != null;

  final List<String> _discountTypes = ['Percentage', 'Fixed Amount'];

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        DiscountModel? discount;
        try { discount = await context.read<DiscountsRepository>().getDiscountById(widget.discountId!); }
        catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'دریافت اطلاعات تخفیف ناموفق بود. دوباره تلاش کنید.')))); }
        if (discount != null) {
          _titleController.text = discount.title;
          _codeController.text = discount.code;
          _valueController.text = discount.type == 'percentage' ? discount.value.toString() : discount.value.toStringAsFixed(0);
          if (discount.type != 'percentage') _valueController.value = _moneyFormatter.formatEditUpdate(const TextEditingValue(), _valueController.value);
          _minPurchaseController.text = discount.minPurchaseAmount?.toString() ?? '';
          _minPurchaseController.value = _moneyFormatter.formatEditUpdate(const TextEditingValue(), _minPurchaseController.value);
          _maxDiscountController.text = discount.maxDiscountAmount?.toString() ?? '';
          _maxDiscountController.value = _moneyFormatter.formatEditUpdate(const TextEditingValue(), _maxDiscountController.value);
          _totalUsageController.text = discount.totalUsageLimit?.toString() ?? '';
          _perUserUsageController.text = discount.perUserUsageLimit?.toString() ?? '';
          _targetPhonesController.text = discount.targetPhones.join('\n');
          _restrictedToCustomers = discount.restrictedToCustomers;
          if (_restrictedToCustomers && discount.targetPhones.isNotEmpty) await _loadExistingTargetCustomers(discount.targetPhones);
          _selectedType = discount.type == 'percentage' ? 'Percentage' : 'Fixed Amount';
          _startDate = discount.startDate;
          _endDate = discount.endDate;
          _isActive = discount.isActive;
          _deliveryChannels
            ..clear()
            ..addAll(discount.deliveryChannels);
          if (_deliveryChannels.isEmpty) _deliveryChannels.add('notification');
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _valueController.dispose();
    _minPurchaseController.dispose();
    _maxDiscountController.dispose();
    _totalUsageController.dispose();
    _perUserUsageController.dispose();
    _targetPhonesController.dispose();
    _customerSearchController.dispose();
    _customerSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final today = Jalali.now();
    final pickedDate = await showPersianDatePicker(
      context: context,
      initialDate: isStart && _startDate != null
          ? Jalali.fromDateTime(_startDate!)
          : (!isStart && _endDate != null ? Jalali.fromDateTime(_endDate!) : today),
      firstDate: Jalali(1402, 1, 1),
      lastDate: Jalali(1500, 12, 29),
      helpText: isStart ? 'انتخاب تاریخ شروع' : 'انتخاب تاریخ پایان',
      initialEntryMode: PersianDatePickerEntryMode.calendar,
    );
    if (pickedDate != null) {
      setState(() {
        if (isStart) {
          _startDate = pickedDate.toDateTime();
        } else {
          _endDate = pickedDate.toDateTime();
        }
      });
    }
  }


  Future<void> _loadExistingTargetCustomers(List<String> phones) async {
    final repository = context.read<CustomersRepository>();
    for (final phone in phones) {
      try {
        final matches = await repository.getCustomers(page: 1, pageSize: 8, searchQuery: phone);
        UserModel? customer;
        for (final item in matches) {
          if (item.phone?.trim() == phone.trim()) { customer = item; break; }
        }
        if (customer != null) _selectedCustomers[customer.id] = customer;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _searchCustomers(String value) {
    _customerSearchDebounce?.cancel();
    final request = ++_customerSearchRequest;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() { _customerSuggestions = []; _customerSearchLoading = false; });
      return;
    }
    setState(() => _customerSearchLoading = true);
    _customerSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final matches = await context.read<CustomersRepository>().getCustomers(page: 1, pageSize: 8, searchQuery: query);
        if (!mounted || request != _customerSearchRequest) return;
        setState(() { _customerSuggestions = matches; _customerSearchLoading = false; });
      } catch (_) {
        if (!mounted || request != _customerSearchRequest) return;
        setState(() { _customerSuggestions = []; _customerSearchLoading = false; });
      }
    });
  }

  void _selectCustomer(UserModel customer) {
    if (customer.phone?.trim().isNotEmpty != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای این مشتری شماره تلفن ثبت نشده است.')));
      return;
    }
    setState(() {
      _selectedCustomers[customer.id] = customer;
      _customerSearchController.clear();
      _customerSuggestions = [];
      _customerSearchLoading = false;
    });
    _syncTargetPhoneController();
  }

  void _removeCustomer(UserModel customer) {
    setState(() => _selectedCustomers.remove(customer.id));
    _syncTargetPhoneController();
  }

  void _syncTargetPhoneController() {
    _targetPhonesController.text = _selectedCustomers.values
        .map((customer) => customer.phone!.trim()).toSet().join('\\n');
  }

  String _persianDigits(String value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value;
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _normalizedNumber(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var result = value.replaceAll(',', '').replaceAll('٬', '').trim();
    for (var i = 0; i < 10; i++) {
      result = result.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
    }
    return result;
  }

  double _parseNumber(String value) => double.parse(_normalizedNumber(value));

  String? _validatePositiveNumber(String? value, {bool isRequired = false}) {
    if (value == null || value.isEmpty) {
      return isRequired ? 'وارد کردن این مقدار الزامی است.' : null;
    }
    final num = double.tryParse(_normalizedNumber(value));
    if (num == null) return 'یک عدد معتبر وارد کنید.';
    if (num < 0 || (isRequired && num == 0)) return isRequired ? 'مقدار باید بیشتر از صفر باشد.' : 'مقدار نمی‌تواند منفی باشد.';
    return null;
  }


  Future<void> _submitForm({bool sendNow = false}) async {
    if (_formKey.currentState!.validate()) {
      if (_deliveryChannels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حداقل یک کانال ارسال را انتخاب کنید.'), backgroundColor: AppColors.error),
        );
        return;
      }
      if (_selectedType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نوع تخفیف را انتخاب کنید'), backgroundColor: AppColors.error),
        );
        return;
      }
      if (_startDate == null || _endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تاریخ شروع و پایان را انتخاب کنید'), backgroundColor: AppColors.error),
        );
        return;
      }

      if (_endDate!.isBefore(_startDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ پایان باید بعد از تاریخ شروع باشد.'), backgroundColor: AppColors.error));
        return;
      }
      final parsedValue = double.tryParse(_normalizedNumber(_valueController.text)) ?? 0;
      if (_selectedType == 'Percentage' && parsedValue > 100) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درصد تخفیف نباید بیشتر از ۱۰۰ باشد.'), backgroundColor: AppColors.error));
        return;
      }
      setState(() => _isLoading = true);

      final discountData = {
        'title': _titleController.text,
        'code': _codeController.text.toUpperCase(),
        'type': _selectedType == 'Percentage' ? 'percentage' : 'fixed_amount',
        'value': _parseNumber(_valueController.text),
        'min_purchase_amount': _minPurchaseController.text.isEmpty ? null : _parseNumber(_minPurchaseController.text),
        'max_discount_amount': _maxDiscountController.text.isEmpty ? null : _parseNumber(_maxDiscountController.text),
        'total_usage_limit': _totalUsageController.text.isEmpty ? null : int.parse(_totalUsageController.text),
        'per_user_usage_limit': _perUserUsageController.text.trim().isEmpty ? null : int.parse(_perUserUsageController.text.trim()),
        'restricted_to_customers': _restrictedToCustomers,
        'delivery_channels': _deliveryChannels.toList(growable: false),
        'target_phones': _selectedCustomers.isNotEmpty ? _selectedCustomers.values.map((customer) => customer.phone!.trim()).toSet().toList() : _targetPhonesController.text.split(RegExp(r'[,،;；\n]')).map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList(),
        'is_active': _isActive,
        'start_date': _startDate!.toIso8601String(),
        'end_date': _endDate!.toIso8601String(),
      };

      try {
        final provider = context.read<DiscountsProvider>();
        final repository = context.read<DiscountsRepository>();
        final ok = isEditing
            ? await provider.updateDiscount(widget.discountId!, discountData)
            : await provider.createDiscount(discountData);
        if (!ok) throw Exception(provider.error ?? 'ذخیره تخفیف ناموفق بود.');

        String? deliveryMessage;
        Color deliveryColor = AppColors.success;
        if (sendNow) {
          final savedId = isEditing
              ? widget.discountId!
              : await repository.getDiscountIdByCode(_codeController.text.trim().toUpperCase());
          final result = await repository.dispatchDiscountDelivery(
            discountId: savedId,
            channels: _deliveryChannels.toList(growable: false),
          );
          final status = (result['status'] ?? 'failed').toString();
          final sent = (result['sent_count'] as num?)?.toInt() ?? 0;
          final failed = (result['failed_count'] as num?)?.toInt() ?? 0;
          deliveryMessage = switch (status) {
            'completed' => 'کد تخفیف از کانال‌های انتخابی ثبت شد. تعداد ارسال/صف: $sent',
            'partial' => 'ارسال کد تخفیف ناقص بود؛ $sent مورد موفق و $failed مورد ناموفق. جزئیات در تاریخچه موجود است.',
            _ => 'تخفیف ذخیره شد، اما ارسال کانال‌ها ناموفق بود. از تاریخچه وضعیت را بررسی کنید.',
          };
          if (status != 'completed') deliveryColor = Colors.orange;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(deliveryMessage ??
                  (isEditing ? 'تخفیف با موفقیت ویرایش شد.' : 'تخفیف با موفقیت ایجاد شد.')),
              backgroundColor: deliveryColor,
              duration: const Duration(seconds: 5),
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'ذخیره تخفیف ناموفق بود. لطفاً اطلاعات و اتصال را بررسی کنید.')), backgroundColor: AppColors.error),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      appBar: AppBar(
        title: Text(isEditing ? 'ویرایش تخفیف' : 'افزودن تخفیف جدید'),
        backgroundColor: AppColors.getSurface(context),
        foregroundColor: AppColors.getPrimaryText(context),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic Info Card
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اطلاعات تخفیف',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.getPrimaryText(context),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: AppSizes.lg),
                    AppTextField(
                      controller: _titleController,
                      labelText: 'عنوان تخفیف *',
                      hintText: 'مثلاً تخفیف تابستانی',
                      validator: (value) => value!.trim().isEmpty ? 'وارد کردن عنوان تخفیف الزامی است.' : null,
                    ),
                    const SizedBox(height: AppSizes.md),
                    AppTextField(
                      controller: _codeController,
                      labelText: 'کد تخفیف *',
                      hintText: 'تابستان۲۰',
                      textCapitalization: TextCapitalization.characters,
                      validator: (value) => value!.trim().isEmpty ? 'وارد کردن کد تخفیف الزامی است.' : null,
                    ),
                    const SizedBox(height: AppSizes.md),
                    AppDropdown<String>(
                      value: _selectedType,
                      items: _discountTypes.map((type) => DropdownMenuItem(value: type, child: Text(type == 'Percentage' ? 'درصدی' : 'مبلغ ثابت'))).toList(),
                      onChanged: (value) { setState(() { _selectedType = value; if (value == 'Fixed Amount') { _valueController.value = _moneyFormatter.formatEditUpdate(const TextEditingValue(), _valueController.value); } else { _valueController.text = _normalizedNumber(_valueController.text); } }); },
                      labelText: 'نوع تخفیف *',
                      hintText: 'نوع تخفیف را انتخاب کنید',
                    ),
                    const SizedBox(height: AppSizes.md),
                    AppTextField(
                      controller: _valueController,
                      labelText: _selectedType == 'Fixed Amount' ? 'مبلغ (تومان) *' : 'مقدار (درصد) *',
                      hintText: '۰',
                      keyboardType: TextInputType.number,
                      inputFormatters: _selectedType == 'Fixed Amount' ? [_moneyFormatter] : const [],
                      prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedFilter),
                      validator: (value) => _validatePositiveNumber(value, isRequired: true),
                    ),
                    const SizedBox(height: AppSizes.md),
                    // Date Pickers
                    Wrap(
                      spacing: AppSizes.md,
                      runSpacing: AppSizes.md,
                      children: [
                        SizedBox(
                          width: MediaQuery.of(context).size.width < 600 ? double.infinity : 250,
                          child: GestureDetector(
                            onTap: () => _pickDate(context, true),
                            child: AbsorbPointer(
                              child: AppTextField(
                                labelText: 'تاریخ شروع *',
                                hintText: _startDate == null ? 'انتخاب تاریخ' : _persianDigits(Jalali.fromDateTime(_startDate!).formatCompactDate()),
                                prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01, size: 20),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        SizedBox(
                          width: MediaQuery.of(context).size.width < 600 ? double.infinity : 250,
                          child: GestureDetector(
                            onTap: () => _pickDate(context, false),
                            child: AbsorbPointer(
                              child: AppTextField(
                                labelText: 'تاریخ پایان *',
                                hintText: _endDate == null ? 'انتخاب تاریخ' : _persianDigits(Jalali.fromDateTime(_endDate!).formatCompactDate()),
                                prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01, size: 20),
                              ),
                            ),
                          ),
                        ),
                          ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),

              // Discount delivery channels
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'کانال‌های ارسال کد تخفیف',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.getPrimaryText(context),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'مشخص کنید این تخفیف از چه مسیرهایی برای مشتریان اطلاع‌رسانی شود.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.getSecondaryText(context),
                          ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    CheckboxListTile(
                      value: _deliveryChannels.contains('banner'),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _deliveryChannels.add('banner');
                        } else {
                          _deliveryChannels.remove('banner');
                        }
                      }),
                      title: const Text('بنر رستوران'),
                      subtitle: const Text('نمایش کد تخفیف در بنرهای فعال'),
                      secondary: const HugeIcon(icon: HugeIcons.strokeRoundedImage01),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _deliveryChannels.contains('notification'),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _deliveryChannels.add('notification');
                        } else {
                          _deliveryChannels.remove('notification');
                        }
                      }),
                      title: const Text('اعلان داخل اپلیکیشن'),
                      subtitle: const Text('ثبت اعلان برای مشتریان هدف'),
                      secondary: const HugeIcon(icon: HugeIcons.strokeRoundedNotification01),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _deliveryChannels.contains('sms'),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _deliveryChannels.add('sms');
                        } else {
                          _deliveryChannels.remove('sms');
                        }
                      }),
                      title: const Text('پیامک'),
                      subtitle: const Text('ارسال از طریق پنل پیامکی متصل به CRM'),
                      secondary: const HugeIcon(icon: HugeIcons.strokeRoundedMessage01),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_deliveryChannels.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSizes.sm),
                        child: Text(
                          'حداقل یک کانال ارسال را انتخاب کنید.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSizes.sm),
                      child: Text(
                        'نکته: ارسال پیامک به فعال بودن بازاریابی پیامکی و رضایت مشتری نیاز دارد. برای کانال بنر نیز باید حداقل یک بنر فعال دارای تصویر وجود داشته باشد.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.getSecondaryText(context),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),

              // Limits & Conditions Card
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'محدودیت‌ها و شرایط استفاده',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.getPrimaryText(context),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: AppSizes.lg),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fieldWidth = constraints.maxWidth < 600
                            ? constraints.maxWidth
                            : 320.0;
                        return Wrap(
                          spacing: AppSizes.md,
                          runSpacing: AppSizes.md,
                          children: [
                        SizedBox(
                          width: fieldWidth,
                          child: AppTextField(
                            controller: _minPurchaseController,
                            labelText: 'حداقل مبلغ خرید (تومان)',
                            hintText: '۰',
                            keyboardType: TextInputType.number,
                            inputFormatters: [_moneyFormatter],
                            prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedFilter),
                            validator: (value) => _validatePositiveNumber(value),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: AppTextField(
                            controller: _maxDiscountController,
                            labelText: 'حداکثر مبلغ تخفیف (تومان)',
                            hintText: '۰',
                            keyboardType: TextInputType.number,
                            validator: (value) => _validatePositiveNumber(value),
                          ),
                        ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSizes.md),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fieldWidth = constraints.maxWidth < 600
                            ? constraints.maxWidth
                            : 320.0;
                        return Wrap(
                          spacing: AppSizes.md,
                          runSpacing: AppSizes.md,
                          children: [
                            SizedBox(
                              width: fieldWidth,
                              child: AppTextField(
                                controller: _totalUsageController,
                                labelText: 'سقف کل استفاده',
                                hintText: 'مثلاً ۱۰۰',
                                keyboardType: TextInputType.number,
                                validator: (value) => _validatePositiveNumber(value),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),

              // Customer targeting section
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('محدودسازی کد برای مشتریان خاص', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSizes.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('فقط شماره‌های مشخص‌شده بتوانند کد را مصرف کنند'),
                    subtitle: const Text('شماره‌ها باید از قبل در پروفایل مشتریان ثبت شده باشند.'),
                    value: _restrictedToCustomers,
                    onChanged: (value) => setState(() => _restrictedToCustomers = value),
                  ),
                  if (_restrictedToCustomers) ...[
                    const SizedBox(height: AppSizes.sm),
                    AppTextField(
                      controller: _customerSearchController,
                      labelText: 'جست‌وجوی مشتری با شماره یا نام *',
                      hintText: 'شماره موبایل یا نام مشتری را وارد کنید',
                      prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedUserGroup),
                      onChanged: _searchCustomers,
                    ),
                    if (_customerSearchLoading)
                      const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                    else if (_customerSearchController.text.trim().isNotEmpty && _customerSuggestions.isEmpty)
                      const Padding(padding: EdgeInsets.all(10), child: Text('مشتری‌ای با این مشخصات پیدا نشد.'))
                    else if (_customerSuggestions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _customerSuggestions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = _customerSuggestions[index];
                            final selected = _selectedCustomers.containsKey(customer.id);
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(radius: 17, child: Text(customer.fullName.isNotEmpty ? customer.fullName[0] : 'م')),
                              title: Text(customer.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('تلفن: ${customer.phone ?? 'ثبت نشده'}\nشناسه: ${customer.id}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: HugeIcon(icon: selected ? HugeIcons.strokeRoundedCheckmarkCircle02 : HugeIcons.strokeRoundedAdd01, color: selected ? Colors.green : null),
                              onTap: selected ? null : () => _selectCustomer(customer),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: AppSizes.sm),
                    if (_selectedCustomers.isNotEmpty)
                      Align(alignment: Alignment.centerRight, child: Text('مشتریان انتخاب‌شده (${_selectedCustomers.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                    if (_selectedCustomers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedCustomers.values.map((customer) => InputChip(
                            avatar: const HugeIcon(icon: HugeIcons.strokeRoundedUserGroup, size: 16),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 210),
                              child: Text('${customer.fullName} • ${customer.phone}', overflow: TextOverflow.ellipsis),
                            ),
                            onDeleted: () => _removeCustomer(customer),
                          )).toList(),
                        ),
                      )
                    else
                      const Text('با انتخاب مشتری، پروفایل او به شکل چیپ در پایین نمایش داده می‌شود.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Offstage(
                      offstage: true,
                      child: AppTextField(
                        controller: _targetPhonesController,
                        validator: (value) => _restrictedToCustomers && _selectedCustomers.isEmpty && (value == null || value.trim().isEmpty) ? 'حداقل یک مشتری انتخاب کنید.' : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSizes.md),
                  AppTextField(
                    controller: _perUserUsageController,
                    labelText: 'سقف استفاده برای هر مشتری (اختیاری)',
                    hintText: 'مثلاً ۱',
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final n = int.tryParse(value.trim());
                      return n == null || n < 1 ? 'عدد صحیح بزرگ‌تر از صفر وارد کنید.' : null;
                    },
                  ),
                ]),
              ),
              const SizedBox(height: AppSizes.lg),

              // Settings Card
              AppCard(
                child: SwitchListTile(
                  title: const Text('تخفیف فعال باشد'),
                  subtitle: const Text('در صورت غیرفعال بودن، مشتریان نمی‌توانند از این تخفیف استفاده کنند.'),
                  value: _isActive,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) => setState(() => _isActive = val),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              
              // Action Buttons
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSizes.md,
                runSpacing: AppSizes.md,
                children: [
                  AppButton(
                    label: AppStrings.cancel,
                    type: AppButtonType.outline,
                    width: 120,
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    label: AppStrings.save,
                    isLoading: _isLoading,
                    width: 120,
                    onPressed: _isLoading ? null : () => _submitForm(),
                  ),
                  AppButton(
                    label: 'ذخیره و ارسال',
                    isLoading: _isLoading,
                    width: 160,
                    onPressed: _isLoading ? null : () => _submitForm(sendNow: true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}