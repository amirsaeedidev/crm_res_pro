import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/tickets_provider.dart';

class TicketDetailsScreen extends StatefulWidget {
  final String ticketId;
  const TicketDetailsScreen({super.key, required this.ticketId});
  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  final _replyController = TextEditingController();
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<TicketsProvider>().fetchTicket(widget.ticketId); }); }
  @override
  void dispose() { _replyController.dispose(); super.dispose(); }


  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('جزئیات تیکت')),
    body: Consumer<TicketsProvider>(builder: (context, provider, _) {
      final ticket = provider.selectedTicket;
      if (provider.isLoading && ticket == null) return const Center(child: CircularProgressIndicator());
      if (provider.error != null && ticket == null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(provider.error!, textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton(onPressed: () => provider.fetchTicket(widget.ticketId), child: const Text('تلاش مجدد'))])));
      if (ticket == null) return const Center(child: Text('تیکت پیدا نشد.'));
      return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(ticket.subject, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text('مشتری: ${ticket.customerName.isEmpty ? 'نام ثبت نشده' : ticket.customerName}'), Text('تلفن: ${ticket.customerPhone.isEmpty ? 'ثبت نشده' : ticket.customerPhone}'), Text('ایمیل: ${ticket.customerEmail.isEmpty ? 'ثبت نشده' : ticket.customerEmail}'), const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: ticket.status, decoration: const InputDecoration(labelText: 'وضعیت تیکت', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'open', child: Text('باز')), DropdownMenuItem(value: 'answered', child: Text('پاسخ داده‌شده')), DropdownMenuItem(value: 'closed', child: Text('بسته'))], onChanged: provider.isWorking ? null : (value) async { if (value != null) { final ok = await provider.updateStatus(ticket.id, value); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'وضعیت ذخیره شد.' : provider.error ?? 'تغییر وضعیت ناموفق بود.'))); } })]))),
        const SizedBox(height: 12), Text('گفت‌وگو', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        Expanded(child: ticket.messages.isEmpty ? const Center(child: Text('هنوز پیامی در این تیکت ثبت نشده است.')) : ListView.separated(itemCount: ticket.messages.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) { final message = ticket.messages[index]; return Align(alignment: message.isAdmin ? Alignment.centerLeft : Alignment.centerRight, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Card(color: message.isAdmin ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message.senderName?.isNotEmpty == true ? message.senderName! : (message.isAdmin ? 'مدیر' : 'مشتری'), style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(message.message), const SizedBox(height: 6), Text(message.createdAt.toLocal().toString(), style: Theme.of(context).textTheme.labelSmall)]))))); })),
        const SizedBox(height: 10), if (ticket.status != 'closed') Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _replyController, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'پاسخ مدیر', hintText: 'متن پاسخ را بنویسید…', border: OutlineInputBorder()))), const SizedBox(width: 8), IconButton.filled(onPressed: provider.isWorking ? null : () async { final text = _replyController.text.trim(); if (text.isEmpty) return; final ok = await provider.reply(ticket.id, text); if (!context.mounted) return; if (ok) _replyController.clear(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'پاسخ ارسال شد.' : provider.error ?? 'ارسال پاسخ ناموفق بود.'))); }, icon: provider.isWorking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send))]) else const Padding(padding: EdgeInsets.all(8), child: Text('این تیکت بسته شده است. برای پاسخ مجدد ابتدا وضعیت آن را باز کنید.'))
      ]));
    }),
  );
}
