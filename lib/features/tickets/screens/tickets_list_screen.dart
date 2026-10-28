
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../providers/tickets_provider.dart';

class TicketsListScreen extends StatefulWidget {
  const TicketsListScreen({super.key});
  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen> {
  final _searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<TicketsProvider>().fetchTickets(); });
  }
  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  String _statusLabel(String status) => switch (status) {'open' => 'باز', 'answered' => 'پاسخ داده‌شده', 'closed' => 'بسته', _ => status};

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('مدیریت تیکت‌ها', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))), IconButton(onPressed: () => context.read<TicketsProvider>().fetchTickets(), tooltip: 'بارگذاری مجدد', icon: const Icon(Icons.refresh))]),
      const SizedBox(height: 12),
      Consumer<TicketsProvider>(builder: (context, provider, _) => Wrap(spacing: 8, runSpacing: 8, children: [
        _countCard('کل دریافتی', provider.counts['total'] ?? 0, Icons.inbox_outlined, Colors.blue),
        _countCard('دریافتی باز', provider.counts['received'] ?? 0, Icons.mark_email_unread_outlined, Colors.orange),
        _countCard('خوانده‌نشده', provider.counts['unread'] ?? 0, Icons.markunread_outlined, Colors.red),
        _countCard('پاسخ‌داده‌شده', provider.counts['answered'] ?? 0, Icons.mark_email_read_outlined, Colors.green),
      ])),
      const SizedBox(height: 16),
      TextField(controller: _searchController, decoration: InputDecoration(labelText: 'جست‌وجو در عنوان تیکت', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _searchController.clear(); context.read<TicketsProvider>().setSearch(''); }, icon: const Icon(Icons.clear)), border: const OutlineInputBorder()), onSubmitted: (value) => context.read<TicketsProvider>().setSearch(value)),
      const SizedBox(height: 12),
      Consumer<TicketsProvider>(builder: (context, provider, _) => DropdownButtonFormField<String>(initialValue: provider.status, decoration: const InputDecoration(labelText: 'وضعیت', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'all', child: Text('همه')), DropdownMenuItem(value: 'received', child: Text('دریافتی باز')), DropdownMenuItem(value: 'unread', child: Text('خوانده‌نشده')), DropdownMenuItem(value: 'answered', child: Text('پاسخ داده‌شده')), DropdownMenuItem(value: 'closed', child: Text('بسته'))], onChanged: (value) { if (value != null) provider.setStatus(value); })),
      const SizedBox(height: 12),
      Expanded(child: Consumer<TicketsProvider>(builder: (context, provider, _) {
        if (provider.isLoading && provider.tickets.isEmpty) return const Center(child: CircularProgressIndicator());
        if (provider.error != null && provider.tickets.isEmpty) return _error(provider.error!, provider.fetchTickets);
        if (provider.tickets.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inbox_outlined, size: 48), SizedBox(height: 12), Text('هیچ تیکتی برای این فیلتر ثبت نشده است.')]));
        return Column(children: [Expanded(child: ListView.separated(itemCount: provider.tickets.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) {
          final ticket = provider.tickets[index];
          final statusColor = ticket.isUnread ? Colors.red : (ticket.status == 'open' ? Colors.orange : (ticket.status == 'answered' ? Colors.green : Colors.grey));
          return Card(child: ListTile(leading: CircleAvatar(backgroundColor: statusColor.withValues(alpha: .12), child: Icon(Icons.support_agent, color: statusColor)), title: Text(ticket.subject, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('${ticket.customerName.isEmpty ? ticket.customerEmail : ticket.customerName}  •  ${ticket.customerPhone}\n${ticket.createdAt.toLocal()}'), isThreeLine: true, trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Chip(label: Text(_statusLabel(ticket.status))), if (ticket.isUnread) const Text('خوانده‌نشده', style: TextStyle(color: Colors.red, fontSize: 11))]), onTap: () => context.push('/tickets/${ticket.id}')));
        })), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: provider.currentPage > 1 ? () => provider.changePage(provider.currentPage - 1) : null, icon: const Icon(Icons.chevron_right)), Text('صفحه ${provider.currentPage}'), IconButton(onPressed: provider.tickets.length == 20 ? () => provider.changePage(provider.currentPage + 1) : null, icon: const Icon(Icons.chevron_left))])]);
      }))
    ]),
  );

  Widget _countCard(String title, int value, IconData icon, Color color) => Container(
    width: 160,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .25))),
    child: Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 12)), Text(value.toString(), style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: color))]))]),
  );

  Widget _error(String error, Future<void> Function() retry) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, color: Colors.red, size: 42), const SizedBox(height: 8), Text(error, textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد'))]));
}
