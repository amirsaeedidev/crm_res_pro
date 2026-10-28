import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/widgets/app_button.dart';
import '../../models/order_model.dart';
import '../../core/services/receipt_pdf_service.dart';

class InvoicePrintDialog extends StatefulWidget {
  final OrderModel order;
  final String invoiceType; // 'customer' or 'kitchen'

  const InvoicePrintDialog({
    super.key,
    required this.order,
    this.invoiceType = 'customer',
  });

  static Future<void> show({
    required BuildContext context,
    required OrderModel order,
    String invoiceType = 'customer',
  }) {
    return showDialog(
      context: context,
      builder: (context) => InvoicePrintDialog(
        order: order,
        invoiceType: invoiceType,
      ),
    );
  }

  @override
  State<InvoicePrintDialog> createState() => _InvoicePrintDialogState();
}

class _InvoicePrintDialogState extends State<InvoicePrintDialog> {
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('en_US');
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd HH:mm');
  Map<String, dynamic> _receiptSettings = const {
    'store_name': 'رستوران', 'store_phone': '', 'store_address': '', 'logo_url': '',
    'header_text': '', 'footer_text': 'با تشکر از خرید شما', 'show_logo': false,
    'show_date': true, 'show_customer': true, 'show_phone': true, 'show_order_type': true,
    'show_table_number': true, 'show_queue_number': true, 'show_discount': true, 'show_notes': true,
  };

  @override
  void initState() {
    super.initState();
    _loadReceiptSettings();
  }

  Future<void> _loadReceiptSettings() async {
    try {
      final settings = await ReceiptPdfService.loadReceiptSettings();
      if (mounted) setState(() => _receiptSettings = settings);
    } catch (_) {
      // Preview falls back to safe generic defaults; PDF generation reports errors separately.
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final invoiceType = widget.invoiceType;
    final isKitchen = invoiceType == 'kitchen';
    const receiptWidth = 320.0; // Approx 80mm at ~4px/mm

    // Removed Directionality wrapper to fix IDE glitch
    return Dialog(
      backgroundColor: AppColors.getSurface(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isKitchen ? 'پیش‌نمایش فاکتور آشپزخانه' : 'پیش‌نمایش فاکتور مشتری',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.getPrimaryText(context),
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Receipt Preview Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSizes.lg),
                child: Center(
                  child: Container(
                    width: receiptWidth,
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.getBorder(context).withValues(alpha: 0.5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo & Header
                        Center(
                          child: Column(
                            children: [
                              if (_receiptSettings['show_logo'] == true && (_receiptSettings['logo_url'] ?? '').toString().trim().isNotEmpty)
                                Image.network(
                                  _receiptSettings['logo_url'].toString(),
                                  height: 48,
                                  width: 110,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Icon(Icons.restaurant_menu, size: 40, color: Colors.grey[800]),
                                )
                              else
                                Icon(Icons.restaurant_menu, size: 40, color: Colors.grey[800]),
                              const SizedBox(height: AppSizes.sm),
                              Text(
                                (_receiptSettings['store_name'] ?? 'رستوران').toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[900]),
                              ),
                              if ((_receiptSettings['header_text'] ?? '').toString().trim().isNotEmpty)
                                Text(_receiptSettings['header_text'].toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              if ((_receiptSettings['store_address'] ?? '').toString().trim().isNotEmpty)
                                Text(_receiptSettings['store_address'].toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              if ((_receiptSettings['store_phone'] ?? '').toString().trim().isNotEmpty)
                                Text('تلفن: ${_receiptSettings['store_phone']}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        _dashedDivider(),
                        // Order Info
                        _buildReceiptRow('شماره سفارش:', '#${order.dailyQueueNumber ?? order.id.substring(0, 8).toUpperCase()}'),
                        if (_receiptSettings['show_queue_number'] != false && order.dailyQueueNumber != null) _buildReceiptRow('نوبت روز:', order.dailyQueueNumber.toString()),
                        if (_receiptSettings['show_date'] != false) _buildReceiptRow('تاریخ:', _dateFormatter.format(order.createdAt.toLocal())),
                        if (!isKitchen && _receiptSettings['show_customer'] != false && order.customerName.isNotEmpty) _buildReceiptRow('مشتری:', order.customerName),
                        if (!isKitchen && _receiptSettings['show_phone'] != false && order.customerPhone.isNotEmpty) _buildReceiptRow('تلفن:', order.customerPhone),
                        if (_receiptSettings['show_order_type'] != false) _buildReceiptRow('نوع:', order.orderType == 'delivery' ? 'ارسال به مقصد' : order.orderType == 'dine_in' ? 'سفارش داخل سالن' : 'تحویل حضوری'),
                        if (_receiptSettings['show_table_number'] != false && order.tableNumber != null) _buildReceiptRow('شماره میز:', order.tableNumber.toString()),

                        if (!isKitchen && _receiptSettings['show_notes'] != false && order.adminNote != null && order.adminNote!.isNotEmpty) ...[
                          const SizedBox(height: AppSizes.sm),
                          Container(
                            padding: const EdgeInsets.all(AppSizes.xs),
                            color: Colors.red[50],
                            child: Text(
                              'یادداشت: ${order.adminNote}',
                              style: TextStyle(fontSize: 12, color: Colors.red[800], fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],

                        _dashedDivider(),
                        
                        // Items
                        if (isKitchen) ...[
                          Text('*** کپی آشپزخانه ***', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                          const SizedBox(height: AppSizes.sm),
                        ] else ...[
                          Text('اقلام سفارش', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                          const SizedBox(height: AppSizes.sm),
                        ],

                        ...order.items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSizes.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.quantity}x  ${item.name}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (!isKitchen)
                                      Text(
                                        _currencyFormatter.format(item.price * item.quantity),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                                if (item.note != null && item.note!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 20.0, top: 2.0),
                                    child: Text(
                                      '- ${item.note}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),

                        _dashedDivider(),

                        // Summary
                        if (!isKitchen) ...[
                          _buildReceiptRow('جمع اولیه:', '${_currencyFormatter.format(order.subtotalAmount > 0 ? order.subtotalAmount : order.items.fold<double>(0, (sum, item) => sum + (item.totalPrice ?? item.price * item.quantity)))} ت'),
                          if (_receiptSettings['show_discount'] != false && order.discountAmount > 0) ...[
                            _buildReceiptRow('تخفیف:', '- ${_currencyFormatter.format(order.discountAmount)} ت'),
                            if ((order.discountCode ?? '').trim().isNotEmpty) _buildReceiptRow('کد تخفیف:', order.discountCode!),
                          ],
                          _dashedDivider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('مبلغ نهایی:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text('${_currencyFormatter.format(order.totalAmount)} ت', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ] else ...[
                          Center(
                            child: Text(
                              'زمان آماده‌سازی: ${_dateFormatter.format(order.createdAt.toLocal())}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                            ),
                          ),
                        ],

                        const SizedBox(height: AppSizes.md),
                        if ((_receiptSettings['footer_text'] ?? '').toString().trim().isNotEmpty)
                          Center(
                            child: Text(
                              _receiptSettings['footer_text'].toString(),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSizes.sm,
                runSpacing: AppSizes.sm,
                children: [
                  AppButton(
                    label: 'بستن',
                    type: AppButtonType.outline,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    label: 'دریافت / اشتراک PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    type: AppButtonType.outline,
                    onPressed: () async {
                      try {
                        await ReceiptPdfService.shareOrderPdf(order, isKitchen: isKitchen);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ساخت PDF ناموفق بود: $error')));
                      }
                    },
                  ),
                  AppButton(
                    label: 'چاپ PDF',
                    icon: Icons.print_outlined,
                    onPressed: () async {
                      try {
                        await ReceiptPdfService.printOrder(order, isKitchen: isKitchen);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پنجره چاپ PDF باز شد.')));
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('چاپ PDF ناموفق بود: $error')));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashedDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: DashedLinePainter(),
      ),
    );
  }
}

class DashedLinePainter extends CustomPainter {
  const DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    double dashWidth = 5, dashSpace = 3;
    double startX = 0;
    final paint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;

    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}