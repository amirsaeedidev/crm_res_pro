import 'package:flutter/material.dart';
import '../../../core/utils/app_error_message.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_textfield.dart';
import '../../../models/discount_model.dart';
import '../../../providers/discounts_provider.dart';
import '../../../repositories/discounts_repository.dart';

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
  
  String? _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isActive = true;
  bool _restrictedToCustomers = false;
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
          _valueController.text = discount.value.toString();
          _minPurchaseController.text = discount.minPurchaseAmount?.toString() ?? '';
          _maxDiscountController.text = discount.maxDiscountAmount?.toString() ?? '';
          _totalUsageController.text = discount.totalUsageLimit?.toString() ?? '';
          _perUserUsageController.text = discount.perUserUsageLimit?.toString() ?? '';
          _targetPhonesController.text = discount.targetPhones.join('\n');
          _restrictedToCustomers = discount.restrictedToCustomers;
          _selectedType = discount.type == 'percentage' ? 'Percentage' : 'Fixed Amount';
          _startDate = discount.startDate;
          _endDate = discount.endDate;
          _isActive = discount.isActive;
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
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: AppColors.getSurface(context),
                  onSurface: AppColors.getPrimaryText(context),
                ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        if (isStart) {
          _startDate = pickedDate;
        } else {
          _endDate = pickedDate;
        }
      });
    }
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

  String? _validatePositiveNumber(String? value, {bool isRequired = false}) {
    if (value == null || value.isEmpty) {
      return isRequired ? 'وارد کردن این مقدار الزامی است.' : null;
    }
    final num = double.tryParse(value);
    if (num == null) return 'یک عدد معتبر وارد کنید.';
    if (num < 0 || (isRequired && num == 0)) return isRequired ? 'مقدار باید بیشتر از صفر باشد.' : 'مقدار نمی‌تواند منفی باشد.';
    return null;
  }


  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
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
      final parsedValue = double.tryParse(_valueController.text) ?? 0;
      if (_selectedType == 'Percentage' && parsedValue > 100) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درصد تخفیف نباید بیشتر از ۱۰۰ باشد.'), backgroundColor: AppColors.error));
        return;
      }
      setState(() => _isLoading = true);

      final discountData = {
        'title': _titleController.text,
        'code': _codeController.text.toUpperCase(),
        'type': _selectedType == 'Percentage' ? 'percentage' : 'fixed_amount',
        'value': double.parse(_valueController.text),
        'min_purchase_amount': _minPurchaseController.text.isEmpty ? null : double.parse(_minPurchaseController.text),
        'max_discount_amount': _maxDiscountController.text.isEmpty ? null : double.parse(_maxDiscountController.text),
        'total_usage_limit': _totalUsageController.text.isEmpty ? null : int.parse(_totalUsageController.text),
        'per_user_usage_limit': _perUserUsageController.text.trim().isEmpty ? null : int.parse(_perUserUsageController.text.trim()),
        'restricted_to_customers': _restrictedToCustomers,
        'target_phones': _targetPhonesController.text.split(RegExp(r'[,،;；\n]')).map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList(),
        'is_active': _isActive,
        'start_date': _startDate!.toIso8601String(),
        'end_date': _endDate!.toIso8601String(),
      };

      try {
        final provider = context.read<DiscountsProvider>();
        final ok = isEditing
            ? await provider.updateDiscount(widget.discountId!, discountData)
            : await provider.createDiscount(discountData);
        if (!ok) throw Exception(provider.error ?? 'ذخیره تخفیف ناموفق بود.');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEditing ? 'تخفیف با موفقیت ویرایش شد.' : 'تخفیف با موفقیت ایجاد شد.'),
              backgroundColor: AppColors.success,
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
                      onChanged: (value) => setState(() => _selectedType = value),
                      labelText: 'نوع تخفیف *',
                      hintText: 'نوع تخفیف را انتخاب کنید',
                    ),
                    const SizedBox(height: AppSizes.md),
                    AppTextField(
                      controller: _valueController,
                      labelText: _selectedType == 'Fixed Amount' ? 'مبلغ (تومان) *' : 'مقدار (درصد) *',
                      hintText: '۰',
                      keyboardType: TextInputType.number,
                      validator: (value) => _validatePositiveNumber(value, isRequired: true),
                    ),
                    const SizedBox(height: AppSizes.md),
                    // Date Pickers
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickDate(context, true),
                            child: AbsorbPointer(
                              child: AppTextField(
                                labelText: 'تاریخ شروع *',
                                hintText: _startDate == null ? 'انتخاب تاریخ' : _persianDigits(DateFormat('yyyy-MM-dd').format(_startDate!)),
                                prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickDate(context, false),
                            child: AbsorbPointer(
                              child: AppTextField(
                                labelText: 'تاریخ پایان *',
                                hintText: _endDate == null ? 'انتخاب تاریخ' : _persianDigits(DateFormat('yyyy-MM-dd').format(_endDate!)),
                                prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
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
                    Wrap(
                      spacing: AppSizes.md,
                      runSpacing: AppSizes.md,
                      children: [
                        SizedBox(
                          width: 250,
                          child: AppTextField(
                            controller: _minPurchaseController,
                            labelText: 'حداقل مبلغ خرید (تومان)',
                            hintText: '۰',
                            keyboardType: TextInputType.number,
                            validator: (value) => _validatePositiveNumber(value),
                          ),
                        ),
                        SizedBox(
                          width: 250,
                          child: AppTextField(
                            controller: _maxDiscountController,
                            labelText: 'حداکثر مبلغ تخفیف (تومان)',
                            hintText: '۰',
                            keyboardType: TextInputType.number,
                            validator: (value) => _validatePositiveNumber(value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    Wrap(
                      spacing: AppSizes.md,
                      runSpacing: AppSizes.md,
                      children: [
                        SizedBox(
                          width: 250,
                          child: AppTextField(
                            controller: _totalUsageController,
                            labelText: 'سقف کل استفاده',
                            hintText: 'مثلاً ۱۰۰',
                            keyboardType: TextInputType.number,
                            validator: (value) => _validatePositiveNumber(value),
                          ),
                        ),
                      ],
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
                      controller: _targetPhonesController,
                      labelText: 'شماره تلفن مشتریان *',
                      hintText: 'هر شماره در یک خط یا جداشده با ویرگول',
                      minLines: 3,
                      maxLines: 7,
                      validator: (value) => _restrictedToCustomers && (value == null || value.trim().isEmpty) ? 'حداقل یک شماره وارد کنید.' : null,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: AppStrings.cancel,
                    type: AppButtonType.outline,
                    width: 120,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSizes.md),
                  AppButton(
                    label: AppStrings.save,
                    isLoading: _isLoading,
                    width: 120,
                    onPressed: _submitForm,
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