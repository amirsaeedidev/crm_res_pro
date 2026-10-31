import 'package:crm_panel/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../models/order_model.dart';
import '../../../providers/orders_provider.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;
import '../../../shared/dialogs/invoice_print_dialog.dart';
import '../widgets/order_refund_manager.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailsScreen({super.key, required this.orderId});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  List<Map<String, dynamic>> _smsStaff = [];
  bool _staffLoading = false;
  bool _staffSaving = false;
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd – HH:mm');
  final TextEditingController _readyTimeController = TextEditingController();
  final TextEditingController _adminNoteController = TextEditingController();

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _statusStepLabel(String status) {
    switch (status) {
      case 'pending':
        return 'در انتظار';
      case 'confirmed':
        return 'تأیید شده';
      case 'preparing':
        return 'در حال آماده‌سازی';
      case 'ready':
        return 'آماده';
      case 'out_for_delivery':
        return 'ارسال شده';
      case 'completed':
        return 'تکمیل‌شده';
      case 'cancelled':
        return 'لغوشده';
      default:
        return 'نامشخص';
    }
  }

  String _orderTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'delivery':
        return 'ارسال';
      case 'pickup':
      case 'takeaway':
        return 'دریافت حضوری';
      case 'dine_in':
        return 'سرو در رستوران';
      default:
        return 'نامشخص';
    }
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'administrator':
        return 'مدیر';
      case 'manager':
        return 'مدیر فروشگاه';
      case 'cashier':
        return 'صندوقدار';
      case 'chef':
      case 'cook':
        return 'آشپز';
      case 'delivery':
      case 'courier':
        return 'پیک';
      case 'staff':
      case 'employee':
        return 'پرسنل';
      default:
        return 'پرسنل';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrdersProvider>().fetchOrderDetails(widget.orderId);
      _loadSmsStaff();
    });
  }

  @override
  void dispose() {
    _readyTimeController.dispose();
    _adminNoteController.dispose();
    super.dispose();
  }


  Future<void> _loadSmsStaff() async {
    if (!mounted) return;
    setState(() => _staffLoading = true);
    try {
      final rows = await SupabaseService.client
          .from('sms_staff_recipients')
          .select('id,name,phone,role_label,order_types,is_active')
          .order('name');
      if (!mounted) return;
      setState(() => _smsStaff = rows.map((row) => Map<String, dynamic>.from(row)).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'دریافت فهرست پرسنل پیامک ناموفق بود. دوباره تلاش کنید.'))));
    } finally {
      if (mounted) setState(() => _staffLoading = false);
    }
  }

  Future<void> _assignStaff(OrdersProvider provider, OrderModel order, String? staffId) async {
    setState(() => _staffSaving = true);
    try {
      await SupabaseService.client.from('orders').update({
        'assigned_staff_id': staffId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', order.id);
      await provider.fetchOrderDetails(order.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرسنل سفارش ذخیره شد؛ در صورت فعال‌بودن پیامک، اعلان به پرسنل منطبق فرستاده می‌شود.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'تخصیص پرسنل به سفارش ناموفق بود. سطح دسترسی را بررسی کنید.'))));
    } finally {
      if (mounted) setState(() => _staffSaving = false);
    }
  }

  Widget _buildStaffAssignment(BuildContext context, OrdersProvider provider, OrderModel order) {
    final eligible = _smsStaff.where((row) {
      if (row['is_active'] == true) return true;
      return row['id']?.toString() == order.assignedStaffId;
    }).toList();
    final ids = eligible.map((e) => e['id'].toString()).toSet();
    final value = order.assignedStaffId != null && ids.contains(order.assignedStaffId) ? order.assignedStaffId : null;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('تخصیص سفارش به پرسنل', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('این انتخاب مشخص می‌کند در صورت فعال بودن پیامک، کدام شخص اعلان این سفارش را دریافت کند. اگر تخصیص ندهید، پرسنل فعال مطابق نوع سفارش پیامک می‌گیرند.'),
      const SizedBox(height: 12),
      if (_staffLoading) const LinearProgressIndicator() else DropdownButtonFormField<String?>(
        initialValue: value,
        decoration: const InputDecoration(labelText: 'پرسنل مسئول', border: OutlineInputBorder()),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(value: null, child: Text('بدون تخصیص؛ براساس نوع سفارش')),
          ...eligible.map((row) => DropdownMenuItem<String?>(value: row['id'].toString(), child: Text('${row['name']} • ${_roleLabel((row['role_label'] ?? '').toString())}'))),
        ],
        onChanged: _staffSaving || _staffLoading ? null : (v) => _assignStaff(provider, order, v),
      ),
      if (!_staffLoading && eligible.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('هنوز پرسنل پیامکی ثبت نشده است. از بخش مرکز پیامک پرسنل را تعریف کنید.')),
    ]));
  }

  List<String> _statusStepsFor(OrderModel order) => order.orderType == 'delivery'
      ? const ['pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed']
      : const ['pending', 'confirmed', 'preparing', 'ready', 'completed'];

  int _getCurrentStep(String status, List<String> steps) => steps.indexOf(status.toLowerCase());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جزئیات سفارش'),
        backgroundColor: AppColors.getSurface(context),
        foregroundColor: AppColors.getPrimaryText(context),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'چاپ فاکتور مشتری',
            onPressed: () {
              final order = context.read<OrdersProvider>().selectedOrder;
              if (order == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اطلاعات سفارش هنوز آماده نیست.')));
                return;
              }
              InvoicePrintDialog.show(context: context, order: order, invoiceType: 'customer');
            },
          ),
          IconButton(
            icon: const Icon(Icons.kitchen_outlined),
            tooltip: 'چاپ فاکتور آشپزخانه',
            onPressed: () {
              final order = context.read<OrdersProvider>().selectedOrder;
              if (order == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اطلاعات سفارش هنوز آماده نیست.')));
                return;
              }
              InvoicePrintDialog.show(context: context, order: order, invoiceType: 'kitchen');
            },
          ),
        ],
      ),
      body: Consumer<OrdersProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingDetails) {
            return const Center(child: AppLoading());
          }

          if (provider.detailsError != null) {
            return app_error.AppErrorWidget(
              message: provider.detailsError!,
              onRetry: () => provider.fetchOrderDetails(widget.orderId),
            );
          }

          final order = provider.selectedOrder;

          if (order == null) {
            return const EmptyWidget(
              title: 'سفارش پیدا نشد',
              message: 'سفارش موردنظر در دسترس نیست یا حذف شده است.',
              icon: Icons.receipt_long_outlined,
            );
          }

          if (order.estimatedReadyMinutes != null && _readyTimeController.text.isEmpty) {
            _readyTimeController.text = order.estimatedReadyMinutes.toString();
          }
          if (_adminNoteController.text.isEmpty && (order.adminNote ?? '').isNotEmpty) {
            _adminNoteController.text = order.adminNote!;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusStepper(context, provider, order),
                const SizedBox(height: AppSizes.lg),
                _buildOrderTypeInfo(context, order),
                const SizedBox(height: AppSizes.lg),
                _buildStaffAssignment(context, provider, order),
                const SizedBox(height: AppSizes.lg),
                _buildReadyTimeControl(context, provider, order),
                const SizedBox(height: AppSizes.lg),
                _buildAdminNoteControl(context, provider, order),
                const SizedBox(height: AppSizes.lg),
                _buildItemsList(context, order),
                const SizedBox(height: AppSizes.lg),
                _buildSummary(context, order),
                const SizedBox(height: AppSizes.lg),
                OrderRefundManager(orderId: order.id, status: order.status, totalAmount: order.totalAmount),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusStepper(BuildContext context, OrdersProvider provider, OrderModel order) {
    final steps = _statusStepsFor(order);
    final currentStep = _getCurrentStep(order.status, steps);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'وضعیت سفارش',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSizes.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(steps.length, (index) {
                bool isCompleted = index < currentStep;
                bool isActive = index == currentStep;
                
                return Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSizes.sm),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted 
                                ? AppColors.success 
                                : (isActive ? AppColors.primary : AppColors.getBorder(context)),
                          ),
                          child: Icon(
                            isCompleted ? Icons.check : Icons.circle,
                            color: Colors.white,
                            size: isActive ? 16 : 12,
                          ),
                        ),
                        const SizedBox(height: AppSizes.xs),
                        Text(
                          _statusStepLabel(steps[index]),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isActive ? AppColors.primary : AppColors.getSecondaryText(context),
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    if (index < steps.length - 1)
                      Container(
                        width: 60,
                        height: 2,
                        color: isCompleted ? AppColors.success : AppColors.getBorder(context),
                      ),
                  ],
                );
              }),
            ),
          ),
          if (order.status == 'cancelled') ...[
            const SizedBox(height: AppSizes.md),
            const Text('این سفارش لغو شده است.', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ] else if (currentStep >= 0 && currentStep < steps.length - 1) ...[
            const SizedBox(height: AppSizes.lg),
            AppButton(
              label: 'ثبت وضعیت بعدی',
              icon: Icons.arrow_forward,
              isLoading: provider.isUpdatingStatus,
              onPressed: () async {
                final ok = await provider.updateOrderStatus(order.id, steps[currentStep + 1]);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'وضعیت سفارش به‌روزرسانی شد.' : provider.detailsError ?? 'تغییر وضعیت ناموفق بود.')));
              },
            ),
            if (order.status != 'completed') ...[
              const SizedBox(height: AppSizes.sm),
              OutlinedButton.icon(
                onPressed: provider.isUpdatingStatus ? null : () async {
                  final ok = await provider.updateOrderStatus(order.id, 'cancelled');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'سفارش لغو شد.' : provider.detailsError ?? 'لغو سفارش ناموفق بود.')));
                },
                icon: const Icon(Icons.cancel_outlined), label: const Text('لغو سفارش'),
              ),
            ],
          ]
        ],
      ),
    );
  }

  Widget _buildOrderTypeInfo(BuildContext context, OrderModel order) {
    IconData icon = Icons.receipt_long;
    String title = 'اطلاعات سفارش';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: AppSizes.sm),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text('نام مشتری:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
          Text(order.customerName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSizes.sm),
          Text('شماره تماس مشتری:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
          Text(order.customerPhone.isEmpty ? 'ثبت نشده' : order.customerPhone, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSizes.sm),
          Text('نوع سفارش:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
          Text(_orderTypeLabel(order.orderType), style: Theme.of(context).textTheme.bodyMedium),
          if (order.orderType == 'dine_in' && order.tableNumber != null) ...[
            const SizedBox(height: AppSizes.sm),
            Text('شماره میز:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
            Text('میز ${_persianDigits(order.tableNumber)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
          
          if (order.adminNote != null && order.adminNote!.isNotEmpty) ...[
            const Divider(height: AppSizes.lg),
            Text('یادداشت مدیر:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.bold)),
            Text(order.adminNote!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.error)),
          ]
        ],
      ),
    );
  }

  Widget _buildReadyTimeControl(BuildContext context, OrdersProvider provider, OrderModel order) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'زمان تقریبی آماده‌سازی (دقیقه)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: _readyTimeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: AppColors.primary),
            onPressed: provider.isUpdatingStatus ? null : () async {
              final minutes = int.tryParse(_readyTimeController.text.trim());
              if (minutes == null || minutes < 1) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('زمان باید عدد صحیح مثبت باشد.')));
                return;
              }
              final ok = await provider.updateEstimatedDeliveryTime(order.id, minutes);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'زمان آماده‌سازی ذخیره شد.' : provider.detailsError ?? 'ذخیره زمان ناموفق بود.')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdminNoteControl(BuildContext context, OrdersProvider provider, OrderModel order) {
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('یادداشت مدیر', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: AppSizes.sm),
      TextField(controller: _adminNoteController, minLines: 2, maxLines: 5, decoration: const InputDecoration(hintText: 'یادداشت داخلی سفارش…', border: OutlineInputBorder())),
      const SizedBox(height: AppSizes.sm),
      Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
        onPressed: provider.isUpdatingStatus ? null : () async {
          final ok = await provider.updateOrderAdminNote(order.id, _adminNoteController.text);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'یادداشت ذخیره شد.' : provider.detailsError ?? 'ذخیره یادداشت ناموفق بود.')));
        }, icon: const Icon(Icons.save_outlined), label: const Text('ذخیره یادداشت'),
      )),
    ]));
  }

  Widget _buildItemsList(BuildContext context, OrderModel order) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اقلام سفارش',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSizes.md),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final item = order.items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_persianDigits(item.quantity)} × ${item.name}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (item.note != null && item.note!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppRadius.small),
                                ),
                                child: Text(
                                  'یادداشت این مورد: ${item.note}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${_persianDigits(item.price * item.quantity)} تومان',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, OrderModel order) {
    return AppCard(
      child: Column(
        children: [
          _buildSummaryRow(context, 'جمع جزء', '${_persianDigits(order.totalAmount)} تومان'),
          const SizedBox(height: AppSizes.sm),
          _buildSummaryRow(context, 'هزینه ارسال', '۰ تومان'), // Assuming fee is included or 0 for now
          const Divider(height: AppSizes.lg),
          _buildSummaryRow(
            context,
            'مبلغ کل',
            '${_persianDigits(order.totalAmount)} تومان',
            isTotal: true,
          ),
          const SizedBox(height: AppSizes.sm),
          _buildSummaryRow(
            context,
            'تاریخ سفارش',
            _persianDigits(_dateFormatter.format(order.createdAt.toLocal())),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
              : Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.getSecondaryText(context)),
        ),
        Text(
          value,
          style: isTotal
              ? Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)
              : Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}