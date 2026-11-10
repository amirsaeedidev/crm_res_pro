import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/app_search.dart';
import '../../../core/widgets/custom_chip.dart';
import '../../../models/order_model.dart';
import '../../../providers/orders_provider.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;
import '../../../shared/widgets/pagination_widget.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  final TextEditingController _searchController = TextEditingController();
  RealtimeChannel? _ordersChannel;
  bool _realtimeConnected = false;
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    // Fetch initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrdersProvider>().fetchOrders();
      _subscribeToLiveOrders();
    });
  }

  void _subscribeToLiveOrders() {
    _ordersChannel = SupabaseService.client
        .channel('crm-live-orders-screen')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (!mounted || _refreshQueued) return;
            _refreshQueued = true;
            // Coalesce bursts (e.g. order creation followed by trigger updates).
            Future<void>.delayed(const Duration(milliseconds: 250), () {
              _refreshQueued = false;
              if (mounted) context.read<OrdersProvider>().fetchOrders();
            });
          },
        )
        .subscribe((status, error) {
          if (!mounted) return;
          setState(() {
            _realtimeConnected = status == RealtimeSubscribeStatus.subscribed;
          });
        });
  }

  @override
  void dispose() {
    _searchController.dispose();
    final channel = _ordersChannel;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
    }
    super.dispose();
  }

  ChipType _getStatusChipType(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return ChipType.warning;
      case 'confirmed':
      case 'preparing':
        return ChipType.info;
      case 'shipped':
      case 'out_for_delivery':
        return ChipType.primary;
      case 'delivered':
        return ChipType.success;
      case 'cancelled':
        return ChipType.error;
      default:
        return ChipType.neutral;
    }
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'در انتظار';
      case 'confirmed':
        return 'تأیید شده';
      case 'preparing':
        return 'در حال آماده‌سازی';
      case 'ready':
        return 'آماده';
      case 'out_for_delivery':
      case 'shipped':
        return 'ارسال شده';
      case 'delivered':
        return 'تحویل شده';
      case 'completed':
        return 'تکمیل‌شده';
      case 'cancelled':
      case 'canceled':
        return 'لغوشده';
      case 'unknown':
      case '':
        return 'نامشخص';
      default:
        return 'نامشخص';
    }
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    final jalali = Jalali.fromDateTime(date);
    return _persianDigits(
      '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/'
      '${jalali.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'مدیریت سفارش‌ها',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.getPrimaryText(context),
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: _realtimeConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                _realtimeConnected
                    ? 'سفارش‌های زنده فعال است'
                    : 'در حال اتصال به بروزرسانی زنده…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.getSecondaryText(context),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'بروزرسانی دستی سفارش‌ها',
                onPressed: () => context.read<OrdersProvider>().fetchOrders(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          _buildStalledOrdersPanel(context),
          const SizedBox(height: AppSizes.sm),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ('all', 'همه سفارش‌ها'), ('pending', 'در انتظار'), ('confirmed', 'تأییدشده'),
            ('preparing', 'در حال آماده‌سازی'), ('ready', 'آماده'), ('out_for_delivery', 'در حال ارسال'),
            ('completed', 'تکمیل‌شده'), ('cancelled', 'لغوشده'),
          ].map((item) {
            final selected = context.watch<OrdersProvider>().statusFilter == item.$1;
            final color = item.$1 == 'pending' ? AppColors.warning : (item.$1 == 'confirmed' || item.$1 == 'preparing' ? AppColors.info : (item.$1 == 'ready' || item.$1 == 'out_for_delivery' ? AppColors.primary : (item.$1 == 'completed' ? AppColors.success : (item.$1 == 'cancelled' ? AppColors.error : AppColors.getSecondaryText(context)))));
            return ChoiceChip(label: Text(item.$2), selected: selected,
              onSelected: (_) => context.read<OrdersProvider>().setStatusFilter(item.$1),
              backgroundColor: color.withValues(alpha: 0.07), selectedColor: color,
              side: BorderSide(color: color), labelStyle: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w600),
              shape: const StadiumBorder(), showCheckmark: false);
          }).toList()),
          const SizedBox(height: AppSizes.sm),

          // Search Bar
          AppSearch(
            controller: _searchController,
            onChanged: (value) {
              context.read<OrdersProvider>().setSearchQuery(value);
            },
          ),
          const SizedBox(height: AppSizes.lg),

          // Content Area based on State
          Expanded(
            child: Consumer<OrdersProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.orders.isEmpty) {
                  return const Center(child: AppLoading());
                }

                if (provider.error != null && provider.orders.isEmpty) {
                  return app_error.AppErrorWidget(
                    message: provider.error!,
                    onRetry: () => provider.fetchOrders(),
                  );
                }

                if (provider.orders.isEmpty) {
                  return const EmptyWidget(
                    title: 'سفارشی پیدا نشد',
                    message: 'سفارشی با این مشخصات پیدا نشد.',
                    icon: Icons.receipt_long_outlined,
                  );
                }

                return AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                            itemCount: provider.orders.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) => _buildOrderRow(
                              context,
                              provider.orders[index],
                              provider,
                              compact: constraints.maxWidth < 720,
                            ),
                          ),
                        ),
                      ),
                      if (provider.totalPages > 1)
                        Padding(
                          padding: const EdgeInsets.all(AppSizes.md),
                          child: PaginationWidget(
                            currentPage: provider.currentPage,
                            totalPages: provider.totalPages,
                            onPageChanged: provider.changePage,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildOrderRow(
    BuildContext context,
    OrderModel order,
    OrdersProvider provider, {
    required bool compact,
  }) {
    final amount = '${_persianDigits(order.totalAmount.round())} تومان';
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.customerName.isEmpty ? 'مشتری نامشخص' : order.customerName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${_formatDate(order.createdAt)} • #${order.id.substring(0, 8).toUpperCase()}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
      ],
    );
    final paymentAndStatus = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(amount, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        CustomChip(label: _formatStatus(order.status), type: _getStatusChipType(order.status)),
      ],
    );
    final actions = Wrap(
      spacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: 'نمایش سفارش',
          icon: const Icon(Icons.visibility_outlined, color: AppColors.info),
          onPressed: () => context.push('/orders/details/${order.id}'),
        ),
        _buildStatusChangeMenu(context, order),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: AppSizes.sm),
                Row(children: [Expanded(child: paymentAndStatus), actions]),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 4, child: identity),
                Expanded(flex: 2, child: paymentAndStatus),
                actions,
              ],
            ),
    );
  }

  Widget _buildStalledOrdersPanel(BuildContext context) {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 15)).toIso8601String();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.client.from('orders_view').select('id, customer_name, status, created_at, daily_queue_number, total_amount')
          .inFilter('status', ['pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery'])
          .lt('created_at', cutoff).order('created_at', ascending: true).limit(20),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.connectionState == ConnectionState.waiting || rows.isEmpty) return const SizedBox.shrink();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.hourglass_top, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text('سفارش‌های معطل‌مانده (بیش از ۱۵ دقیقه)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              Chip(label: Text(_persianDigits(rows.length))),
            ]),
            const SizedBox(height: 4),
            ...rows.map((row) {
              final created = DateTime.tryParse((row['created_at'] ?? '').toString());
              final minutes = created == null ? 0 : DateTime.now().difference(created.toLocal()).inMinutes;
              final number = row['daily_queue_number'];
              return ListTile(
                dense: true,
                leading: CircleAvatar(child: Text(number == null ? '—' : _persianDigits(number))),
                title: Text((row['customer_name'] ?? 'مشتری').toString()),
                subtitle: Text('${_formatStatus((row['status'] ?? '').toString())} • ${_persianDigits(minutes)} دقیقه معطلی'),
                trailing: IconButton(icon: const Icon(Icons.open_in_new), tooltip: 'نمایش سفارش',
                  onPressed: () => context.push('/orders/details/${row['id']}')),
              );
            }),
          ]),
        );
      },
    );
  }

  String? _nextStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'confirmed';
      case 'confirmed':
        return 'preparing';
      case 'preparing':
        return 'ready';
      case 'ready':
        return 'out_for_delivery';
      case 'out_for_delivery':
      case 'shipped':
        return 'completed';
      default:
        return null;
    }
  }

  Widget _buildStatusChangeMenu(BuildContext context, OrderModel order) {
    final provider = context.read<OrdersProvider>();
    final next = _nextStatus(order.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (next != null)
          TextButton.icon(
            onPressed: provider.isUpdatingStatus
                ? null
                : () async {
                    final ok = await provider.updateOrderStatus(order.id, next);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? 'وضعیت سفارش: ${_formatStatus(next)}'
                            : provider.detailsError ?? 'تغییر وضعیت سفارش ناموفق بود.'),
                      ),
                    );
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text(_formatStatus(next)),
          ),
        PopupMenuButton<String>(
          icon: Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
          tooltip: 'تغییر وضعیت سفارش',
          onSelected: (String newStatus) async {
            final ok = await provider.updateOrderStatus(order.id, newStatus);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok
                  ? 'وضعیت سفارش به «${_formatStatus(newStatus)}» تغییر کرد.'
                  : provider.detailsError ?? 'تغییر وضعیت سفارش ناموفق بود.')),
            );
          },
          itemBuilder: (context) {
            const statuses = [
              'pending',
              'confirmed',
              'preparing',
              'ready',
              'out_for_delivery',
              'completed',
              'cancelled',
            ];
            return statuses.map((status) => PopupMenuItem<String>(
              value: status,
              enabled: status != order.status.toLowerCase(),
              child: Row(
                children: [
                  Icon(Icons.arrow_forward, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: AppSizes.sm),
                  Text(_formatStatus(status)),
                ],
              ),
            )).toList();
          },
        ),
      ],
    );
  }
}