import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../providers/tickets_provider.dart';

class TicketDetailsScreen extends StatefulWidget {
  final String ticketId;

  const TicketDetailsScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TicketsProvider>().fetchTicket(widget.ticketId);
    });
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
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

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _updateStatus(
    BuildContext context,
    TicketsProvider provider,
    String ticketId,
    String status,
  ) async {
    final success = await provider.updateStatus(ticketId, status);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'وضعیت تیکت ذخیره شد.'
              : provider.error ?? 'ذخیره وضعیت تیکت ناموفق بود.',
        ),
      ),
    );
  }

  Future<void> _sendReply(
    BuildContext context,
    TicketsProvider provider,
    String ticketId,
  ) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا متن پاسخ را بنویسید.')),
      );
      return;
    }

    final success = await provider.reply(ticketId, text);
    if (!context.mounted) return;

    if (success) _replyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'پاسخ با موفقیت ارسال شد.' : provider.error ?? 'ارسال پاسخ ناموفق بود.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جزئیات تیکت')),
      body: SafeArea(
        top: false,
        child: Consumer<TicketsProvider>(
          builder: (context, provider, _) {
            final ticket = provider.selectedTicket;

            if (provider.isLoading && ticket == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.error != null && ticket == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 44,
                      ),
                      const SizedBox(height: AppSizes.md),
                      Text(provider.error!, textAlign: TextAlign.center),
                      const SizedBox(height: AppSizes.md),
                      FilledButton.icon(
                        onPressed: provider.isLoading
                            ? null
                            : () => provider.fetchTicket(widget.ticketId),
                        icon: const Icon(Icons.refresh),
                        label: const Text('تلاش دوباره'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (ticket == null) {
              return const Center(child: Text('تیکت موردنظر پیدا نشد.'));
            }

            final currentStatus = const ['open', 'answered', 'closed']
                    .contains(ticket.status)
                ? ticket.status
                : 'open';

            return Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket.subject,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          Wrap(
                            spacing: AppSizes.lg,
                            runSpacing: AppSizes.xs,
                            children: [
                              _infoText(
                                context,
                                'مشتری',
                                ticket.customerName.trim().isEmpty
                                    ? 'نام ثبت نشده'
                                    : ticket.customerName,
                              ),
                              _infoText(
                                context,
                                'تلفن',
                                ticket.customerPhone.trim().isEmpty
                                    ? 'ثبت نشده'
                                    : _persianDigits(ticket.customerPhone),
                              ),
                              _infoText(
                                context,
                                'ایمیل',
                                ticket.customerEmail.trim().isEmpty
                                    ? 'ثبت نشده'
                                    : ticket.customerEmail,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSizes.md),
                          DropdownButtonFormField<String>(
                            initialValue: currentStatus,
                            decoration: const InputDecoration(
                              labelText: 'وضعیت تیکت',
                              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.medium))),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'open',
                                child: Text('باز'),
                              ),
                              DropdownMenuItem(
                                value: 'answered',
                                child: Text('پاسخ داده‌شده'),
                              ),
                              DropdownMenuItem(
                                value: 'closed',
                                child: Text('بسته'),
                              ),
                            ],
                            onChanged: provider.isWorking
                                ? null
                                : (value) {
                                    if (value != null) {
                                      _updateStatus(
                                        context,
                                        provider,
                                        ticket.id,
                                        value,
                                      );
                                    }
                                  },
                          ),
                          if (provider.isWorking) ...[
                            const SizedBox(height: AppSizes.sm),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    'گفت‌وگوی تیکت',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Expanded(
                    child: ticket.messages.isEmpty
                        ? const Center(
                            child: Text('هنوز پیامی در این تیکت ثبت نشده است.'),
                          )
                        : ListView.separated(
                            itemCount: ticket.messages.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSizes.sm),
                            itemBuilder: (context, index) {
                              final message = ticket.messages[index];
                              final sender = message.senderName?.trim();
                              return Align(
                                alignment: message.isAdmin
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 720),
                                  child: Card(
                                    color: message.isAdmin
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.all(AppSizes.md),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sender?.isNotEmpty == true
                                                ? sender!
                                                : (message.isAdmin
                                                    ? 'مدیر'
                                                    : 'مشتری'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: AppSizes.sm),
                                          SelectableText(message.message),
                                          const SizedBox(height: AppSizes.sm),
                                          Text(
                                            _formatDate(message.createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  if (ticket.status != 'closed')
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.10),
                                  borderRadius: AppRadius.mediumAll,
                                ),
                                child: const Icon(
                                  Icons.reply_rounded,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: AppSizes.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'پاسخ به مشتری',
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'پاسخ شما در همین گفت‌وگو ثبت می‌شود.',
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(
                                        color: AppColors.getSecondaryText(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSizes.md),
                          TextField(
                            controller: _replyController,
                            minLines: 3,
                            maxLines: 6,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'متن پاسخ',
                              hintText: 'پاسخ واضح و کامل خود را بنویسید…',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.edit_note_rounded),
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FilledButton.icon(
                              onPressed: provider.isWorking
                                  ? null
                                  : () => _sendReply(context, provider, ticket.id),
                              icon: provider.isWorking
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(
                                provider.isWorking ? 'در حال ارسال…' : 'ارسال پاسخ',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline, color: AppColors.getSecondaryText),
                          const SizedBox(width: AppSizes.sm),
                          const Expanded(
                            child: Text(
                              'این تیکت بسته شده است. برای پاسخ‌گویی دوباره، ابتدا وضعیت آن را به «باز» تغییر دهید.',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _infoText(BuildContext context, String label, String value) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
