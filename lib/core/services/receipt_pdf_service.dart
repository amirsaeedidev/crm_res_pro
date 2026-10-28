import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/order_model.dart';
import 'supabase_service.dart';

class ReceiptPdfService {
  ReceiptPdfService._();

  static Future<Map<String, dynamic>> loadReceiptSettings() => _settings();

  static Future<Map<String, dynamic>> _settings() async {
    try {
      final row = await SupabaseService.client.from('receipt_settings').select('*').eq('id', 'main').maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row);
    } catch (_) {
      // Fallback allows receipts to print even if the settings table is not deployed yet.
    }
    try {
      final row = await SupabaseService.client.from('restaurant_settings').select('company_name,company_phone,company_address').limit(1).maybeSingle();
      if (row != null) {
        return {
          'store_name': row['company_name'] ?? 'رستوران',
          'store_phone': row['company_phone'] ?? '',
          'store_address': row['company_address'] ?? '',
          'show_logo': false,
          'show_date': true,
          'show_customer': true,
          'show_phone': true,
          'show_order_type': true,
          'show_table_number': true,
          'show_queue_number': true,
          'show_discount': true,
          'show_notes': true,
          'paper_size': 'a4',
          'footer_text': 'با تشکر از خرید شما',
        };
      }
    } catch (_) {/* Use safe defaults below. */}
    return const {
      'store_name': 'رستوران', 'store_phone': '', 'store_address': '', 'logo_url': '',
      'header_text': '', 'footer_text': 'با تشکر از خرید شما', 'paper_size': 'a4', 'show_logo': false,
      'show_date': true, 'show_customer': true, 'show_phone': true, 'show_order_type': true,
      'show_table_number': true, 'show_queue_number': true, 'show_discount': true, 'show_notes': true,
    };
  }

  static Future<Uint8List?> _loadLogo(Map<String, dynamic> settings) async {
    if (settings['show_logo'] != true) return null;
    final raw = (settings['logo_url'] ?? '').toString().trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return null;
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty && response.bodyBytes.length < 2 * 1024 * 1024) {
        return response.bodyBytes;
      }
    } catch (_) {/* Do not fail a receipt just because the logo is unavailable. */}
    return null;
  }

  static String _money(num value) => NumberFormat('#,##0.##', 'en_US').format(value);

  static String _orderType(String value) => switch (value) {
    'delivery' => 'ارسال به مقصد',
    'pickup' => 'تحویل حضوری',
    'dine_in' => 'سفارش داخل سالن',
    _ => value,
  };

  static Future<Uint8List> buildOrderPdf(OrderModel order, {bool isKitchen = false}) async {
    final settings = await _settings();
    final fontData = await rootBundle.load('assets/fonts/Lalezar.ttf');
    final font = pw.Font.ttf(fontData);
    final logoBytes = await _loadLogo(settings);
    final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
    final doc = pw.Document(compress: true);
    final paperSize = (settings['paper_size'] ?? 'a4').toString();
    final format = paperSize == 'roll_58'
        ? PdfPageFormat(58 * PdfPageFormat.mm, 250 * PdfPageFormat.mm, marginAll: 4 * PdfPageFormat.mm)
        : paperSize == 'roll_80'
            ? PdfPageFormat(80 * PdfPageFormat.mm, 300 * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm)
            : PdfPageFormat.a4;
    final dateText = DateFormat('yyyy/MM/dd  HH:mm').format(order.createdAt.toLocal());
    final orderNo = order.dailyQueueNumber == null ? order.id.substring(0, order.id.length < 8 ? order.id.length : 8).toUpperCase() : order.dailyQueueNumber.toString();
    final small = paperSize != 'a4';
    final baseStyle = pw.TextStyle(font: font, fontSize: small ? 8 : 10);
    final boldStyle = pw.TextStyle(font: font, fontSize: small ? 9 : 11, fontWeight: pw.FontWeight.bold);
    final direction = pw.TextDirection.rtl;
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      textDirection: direction,
      margin: pw.EdgeInsets.zero,
      build: (context) => [
        if (logo != null) pw.Center(child: pw.Container(width: small ? 40 : 65, height: small ? 40 : 65, child: pw.Image(logo, fit: pw.BoxFit.contain))),
        pw.Center(child: pw.Text((settings['store_name'] ?? 'رستوران').toString(), style: pw.TextStyle(font: font, fontSize: small ? 15 : 20, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
        if ((settings['header_text'] ?? '').toString().trim().isNotEmpty)
          pw.Center(child: pw.Text(settings['header_text'].toString(), style: baseStyle, textAlign: pw.TextAlign.center)),
        if ((settings['store_address'] ?? '').toString().trim().isNotEmpty)
          pw.Center(child: pw.Text(settings['store_address'].toString(), style: baseStyle, textAlign: pw.TextAlign.center)),
        if ((settings['store_phone'] ?? '').toString().trim().isNotEmpty)
          pw.Center(child: pw.Text('تلفن: ${settings['store_phone']}', style: baseStyle, textAlign: pw.TextAlign.center)),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 0.8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(child: pw.Text('شماره سفارش: $orderNo', style: boldStyle)),
          if (settings['show_date'] != false) pw.Text(dateText, style: baseStyle),
        ]),
        if (settings['show_queue_number'] == true && order.dailyQueueNumber != null)
          pw.Text('نوبت روز: ${order.dailyQueueNumber}', style: boldStyle),
        if (settings['show_order_type'] != false) pw.Text('نوع سفارش: ${_orderType(order.orderType)}', style: baseStyle),
        if (settings['show_table_number'] != false && order.tableNumber != null) pw.Text('شماره میز: ${order.tableNumber}', style: baseStyle),
        if (!isKitchen && settings['show_customer'] != false && order.customerName.trim().isNotEmpty) pw.Text('مشتری: ${order.customerName}', style: baseStyle),
        if (!isKitchen && settings['show_phone'] != false && order.customerPhone.trim().isNotEmpty) pw.Text('تلفن مشتری: ${order.customerPhone}', style: baseStyle),
        if (isKitchen) pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Center(child: pw.Text('نسخه آشپزخانه', style: boldStyle))),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          headers: const ['نام غذا', 'تعداد', 'قیمت واحد', 'جمع'],
          data: order.items.map((item) => [
            item.name + ((item.note ?? '').trim().isEmpty ? '' : '\n${item.note}'),
            item.quantity.toString(),
            isKitchen ? '—' : _money(item.price),
            isKitchen ? '—' : _money(item.totalPrice ?? (item.price * item.quantity)),
          ]).toList(growable: false),
          headerStyle: boldStyle,
          cellStyle: baseStyle,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          columnWidths: small ? {0: const pw.FlexColumnWidth(2.5), 1: const pw.FlexColumnWidth(.7), 2: const pw.FlexColumnWidth(1.2), 3: const pw.FlexColumnWidth(1.2)} : null,
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
          cellPadding: pw.EdgeInsets.symmetric(horizontal: small ? 2 : 5, vertical: small ? 3 : 5),
        ),
        pw.SizedBox(height: 6),
        if (!isKitchen) ...[
          _summaryRow('جمع اولیه', _money(order.subtotalAmount > 0 ? order.subtotalAmount : order.items.fold<double>(0, (sum, item) => sum + (item.totalPrice ?? item.price * item.quantity))), baseStyle),
          if (settings['show_discount'] != false && order.discountAmount > 0) ...[
            _summaryRow('تخفیف', '- ${_money(order.discountAmount)}', baseStyle),
            if ((order.discountCode ?? '').trim().isNotEmpty) _summaryRow('کد تخفیف', order.discountCode!, baseStyle),
          ],
          pw.Divider(thickness: 0.8),
          _summaryRow('مبلغ نهایی', '${_money(order.totalAmount)} تومان', boldStyle),
        ],
        if (!isKitchen && settings['show_notes'] != false && (order.adminNote ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 5),
          pw.Text('یادداشت: ${order.adminNote}', style: baseStyle),
        ],
        if ((settings['footer_text'] ?? '').toString().trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text(settings['footer_text'].toString(), style: baseStyle, textAlign: pw.TextAlign.center)),
        ],
      ],
    ));
    return doc.save();
  }

  static pw.Widget _summaryRow(String label, String value, pw.TextStyle style) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: style),
      pw.Text(value, style: style),
    ]),
  );

  static Future<void> printOrder(OrderModel order, {bool isKitchen = false}) async {
    final bytes = await buildOrderPdf(order, isKitchen: isKitchen);
    final name = 'receipt_${order.dailyQueueNumber ?? order.id.substring(0, 8)}.pdf';
    await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
  }

  static Future<void> shareOrderPdf(OrderModel order, {bool isKitchen = false}) async {
    final bytes = await buildOrderPdf(order, isKitchen: isKitchen);
    final name = 'receipt_${order.dailyQueueNumber ?? order.id.substring(0, 8)}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: name);
  }
}
