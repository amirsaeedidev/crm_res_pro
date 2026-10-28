import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/app_search.dart';
import '../../../core/widgets/app_table.dart';
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
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('en_US');
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
        return 'در مسیر ارسال';
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
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
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
                        child: AppTable(
                          minWidth: 900,
                          headers: const [
                            'شماره سفارش',
                            'مشتری',
                            'تاریخ',
                            'مبلغ',
                            'وضعیت',
                            'عملیات'
                          ],
                          rows: provider.orders.map((order) {
                            return [
                              Text(
                                '#${order.id.substring(0, 8).toUpperCase()}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                order.customerName,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.getPrimaryText(context),
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                _formatDate(order.createdAt),
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.getSecondaryText(context),
                                    ),
                              ),
                              Text(
                                '${_persianDigits(_currencyFormatter.format(order.totalAmount))} تومان',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.getPrimaryText(context),
                                    ),
                              ),
                              CustomChip(
                                label: _formatStatus(order.status),
                                type: _getStatusChipType(order.status),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.visibility_outlined, color: AppColors.info),
                                    onPressed: () {
                                      context.push('/orders/details/${order.id}');
                                    },
                                  ),
                                  _buildStatusChangeMenu(context, order),
                                ],
                              ),
                            ];
                          }).toList(),
                        ),
                      ),
                      if (provider.totalPages > 1)
                        Padding(
                          padding: const EdgeInsets.all(AppSizes.md),
                          child: PaginationWidget(
                            currentPage: provider.currentPage,
                            totalPages: provider.totalPages,
                            onPageChanged: (page) {
                              provider.changePage(page);
                            },
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

  Widget _buildStatusChangeMenu(BuildContext context, OrderModel order) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
      tooltip: 'تغییر وضعیت',
      onSelected: (String newStatus) {
        context.read<OrdersProvider>().updateOrderStatus(order.id, newStatus);
      },
      itemBuilder: (context) {
        final statuses = [
          'pending',
          'confirmed',
          'preparing',
          'out_for_delivery',
          'delivered',
          'cancelled'
        ];
        return statuses.map((status) {
          return PopupMenuItem<String>(
            value: status,
            enabled: status != order.status.toLowerCase(),
            child: Row(
              children: [
                Icon(Icons.arrow_forward, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppSizes.sm),
                Text(_formatStatus(status)),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}