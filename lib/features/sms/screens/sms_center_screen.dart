import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../repositories/sms_repository.dart';

class SmsCenterScreen extends StatefulWidget {
  const SmsCenterScreen({super.key});

  @override
  State<SmsCenterScreen> createState() => _SmsCenterScreenState();
}

class _SmsCenterScreenState extends State<SmsCenterScreen>
    with SingleTickerProviderStateMixin {
  final SmsRepository _repo = SmsRepository();
  late final TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  Map<String, dynamic> _settings = {};
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _eligibleCustomers = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _outbox = [];
  List<Map<String, dynamic>> _attempts = [];
  List<Map<String, dynamic>> _stats = [];
  List<Map<String, dynamic>> _activeDiscounts = [];
  String? _selectedDiscountId;
  final Set<String> _selectedCustomers = {};
  final Map<String, TextEditingController> _normalTemplateControllers = {};
  final Map<String, TextEditingController> _patternTemplateControllers = {};
  final Map<String, bool> _templateActive = {};

  final _username = TextEditingController();
  final _apiKey = TextEditingController();
  final _sender = TextEditingController();
  final _defaultBodyId = TextEditingController();
  final _adminPhone = TextEditingController();
  final _maxAttempts = TextEditingController(text: '5');
  final _retryDelay = TextEditingController(text: '60');
  final _campaignName = TextEditingController(text: 'کمپین پیامکی');
  final _campaignMessage = TextEditingController();
  final _campaignBodyId = TextEditingController();
  final _campaignPatternArgs = TextEditingController();
  final _smsCostPerMessage = TextEditingController(text: '0');
  final _otherCampaignCost = TextEditingController(text: '0');
  final _attributionWindowDays = TextEditingController(text: '7');
  final _customerSearch = TextEditingController();
  final _testPhone = TextEditingController();
  final _testMessage = TextEditingController(
    text: 'این یک پیام آزمایشی از پنل مدیریت رستوران است.',
  );
  final _testBodyId = TextEditingController();
  final _testPatternArgs = TextEditingController();

  bool _smsEnabled = false;
  bool _marketingEnabled = false;
  bool _notifyReady = true;
  bool _notifyTicketCustomer = true;
  bool _notifyTicketAdmin = true;
  bool _notifyStaff = true;
  bool _isPattern = false;
  bool _loadingCustomers = false;
  bool _loadingStaff = false;
  bool _loadingLogs = false;
  String _logStatusFilter = 'all';
  String _logEventFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _username,
      _apiKey,
      _sender,
      _defaultBodyId,
      _adminPhone,
      _maxAttempts,
      _retryDelay,
      _campaignName,
      _campaignMessage,
      _campaignBodyId,
      _campaignPatternArgs,
      _smsCostPerMessage,
      _otherCampaignCost,
      _attributionWindowDays,
      _customerSearch,
      _testPhone,
      _testMessage,
      _testBodyId,
      _testPatternArgs,
    ]) {
      c.dispose();
    }
    for (final c in _normalTemplateControllers.values) {
      c.dispose();
    }
    for (final c in _patternTemplateControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        _repo.getSettings(),
        _repo.getTemplates(),
        _repo.getStaff(),
        _repo.getOutbox(),
        _repo.getAttemptLogs(),
        _repo.getDeliveryStats(),
        _repo.getMarketingEligibleCustomers(),
        _repo.getActiveDiscounts(),
      ]);
      if (!mounted) return;
      _settings = Map<String, dynamic>.from(values[0] as Map);
      _templates = List<Map<String, dynamic>>.from(values[1] as List);
      _staff = List<Map<String, dynamic>>.from(values[2] as List);
      _outbox = List<Map<String, dynamic>>.from(values[3] as List);
      _attempts = List<Map<String, dynamic>>.from(values[4] as List);
      _stats = List<Map<String, dynamic>>.from(values[5] as List);
      _eligibleCustomers = List<Map<String, dynamic>>.from(values[6] as List);
      _activeDiscounts = List<Map<String, dynamic>>.from(values[7] as List);
      _applySettingsToForm();
      _applyTemplatesToForm();
    } catch (e) {
      _loadError = AppErrorMessage.from(e, fallback: 'بارگذاری مرکز پیامک ناموفق بود. تنظیمات و اتصال را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySettingsToForm() {
    _username.text = (_settings['username'] ?? '').toString();
    _sender.text = (_settings['sender_number'] ?? '').toString();
    _defaultBodyId.text = (_settings['default_body_id'] ?? '').toString();
    _adminPhone.text = (_settings['admin_notification_phone'] ?? '').toString();
    _maxAttempts.text = (_settings['max_attempts'] ?? 5).toString();
    _retryDelay.text = (_settings['retry_delay_seconds'] ?? 60).toString();
    _smsEnabled = _settings['sms_enabled'] == true;
    _marketingEnabled = _settings['marketing_enabled'] == true;
    _isPattern = _settings['send_mode'] == 'pattern';
    _notifyReady = _settings['notify_order_ready_customer'] != false;
    _notifyTicketCustomer = _settings['notify_ticket_customer'] != false;
    _notifyTicketAdmin = _settings['notify_ticket_admin'] != false;
    _notifyStaff = _settings['notify_new_orders_staff'] != false;
  }

  void _applyTemplatesToForm() {
    for (final template in _templates) {
      final key = (template['event_key'] ?? '').toString();
      _normalTemplateControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      _patternTemplateControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      _normalTemplateControllers[key]!.text = (template['normal_message'] ?? '')
          .toString();
      _patternTemplateControllers[key]!.text =
          (template['pattern_body_id'] ?? '').toString();
      _templateActive[key] = template['is_active'] != false;
    }
  }

  Future<void> _saveSettings() async {
    final attempts = int.tryParse(_maxAttempts.text.trim());
    final delay = int.tryParse(_retryDelay.text.trim());
    if (attempts == null || attempts < 1 || attempts > 10) {
      _toast('تعداد تلاش باید بین ۱ تا ۱۰ باشد.');
      return;
    }
    if (delay == null || delay < 5 || delay > 86400) {
      _toast('فاصله تلاش باید بین ۵ تا ۸۶۴۰۰ ثانیه باشد.');
      return;
    }
    if (_smsEnabled && _username.text.trim().isEmpty) {
      _toast('نام کاربری ملی پیامک الزامی است.');
      return;
    }
    if (_smsEnabled &&
        _apiKey.text.trim().isEmpty &&
        _settings['provider_key_configured'] != true) {
      _toast('API Key ملی پیامک را وارد کنید.');
      return;
    }
    if (_smsEnabled && !_isPattern && _sender.text.trim().isEmpty) {
      _toast('شماره فرستنده برای حالت عادی الزامی است.');
      return;
    }
    if (_smsEnabled &&
        _isPattern &&
        _defaultBodyId.text.trim().isEmpty &&
        _templates.every(
          (t) => ((t['pattern_body_id'] ?? '').toString().trim().isEmpty),
        )) {
      _toast('Body ID برای حالت پترن الزامی است.');
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _repo.saveSettings({
        'p_sms_enabled': _smsEnabled,
        'p_marketing_enabled': _marketingEnabled,
        'p_send_mode': _isPattern ? 'pattern' : 'normal',
        'p_username': _username.text.trim(),
        'p_api_key': _apiKey.text.trim(),
        'p_sender_number': _sender.text.trim(),
        'p_default_body_id': _defaultBodyId.text.trim(),
        'p_admin_notification_phone': _adminPhone.text.trim(),
        'p_notify_order_ready_customer': _notifyReady,
        'p_notify_ticket_customer': _notifyTicketCustomer,
        'p_notify_ticket_admin': _notifyTicketAdmin,
        'p_notify_new_orders_staff': _notifyStaff,
        'p_max_attempts': attempts,
        'p_retry_delay_seconds': delay,
      });
      _apiKey.clear();
      final nested = result['settings'];
      if (nested is Map) _settings = Map<String, dynamic>.from(nested);
      _settings['provider_key_configured'] =
          result['api_key_configured'] == true;
      if (mounted) setState(() {});
      _toast(
        result['api_key_configured'] == true
            ? 'تنظیمات ذخیره شد؛ کلید API به‌صورت امن در Vault نگهداری می‌شود.'
            : 'تنظیمات ذخیره شد؛ برای ارسال واقعی باید API Key را ثبت کنید.',
      );
    } catch (e) {
      _toast('ذخیره تنظیمات پیامک ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTemplates() async {
    setState(() => _saving = true);
    try {
      for (final template in _templates) {
        final key = (template['event_key'] ?? '').toString();
        await _repo.updateTemplate({
          ...template,
          'normal_message': _normalTemplateControllers[key]?.text ?? '',
          'pattern_body_id': _patternTemplateControllers[key]?.text ?? '',
          'is_active': _templateActive[key] ?? true,
        });
      }
      _toast('الگوهای پیامک ذخیره شدند.');
      await _loadAll();
    } catch (e) {
      _toast('ذخیره الگوها ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadMarketingCustomers({String? query}) async {
    setState(() => _loadingCustomers = true);
    try {
      final rows = await _repo.getMarketingEligibleCustomers(query: query);
      if (!mounted) return;
      _eligibleCustomers = rows;
      final validIds = rows.map((r) => r['id'].toString()).toSet();
      _selectedCustomers.removeWhere((id) => !validIds.contains(id));
    } catch (e) {
      _toast('دریافت فهرست مشتریان دارای رضایت ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  Future<void> _queueCampaign() async {
    if (_selectedCustomers.isEmpty) {
      _toast('حداقل یک مشتری دارای رضایت پیامک تبلیغاتی انتخاب کنید.');
      return;
    }
    if (!_isPattern && _campaignMessage.text.trim().isEmpty) {
      _toast('متن پیامک را وارد کنید.');
      return;
    }
    if (_isPattern &&
        _campaignBodyId.text.trim().isEmpty &&
        _defaultBodyId.text.trim().isEmpty) {
      _toast('شناسه الگو (Body ID) را وارد کنید.');
      return;
    }
    if (_isPattern && !_campaignPatternArgs.text.contains('{{track_url}}')) {
      _toast('برای رهگیری کلیک، متغیر {{track_url}} را در آرگومان‌های پترن قرار دهید.');
      return;
    }
    final smsCost = double.tryParse(_smsCostPerMessage.text.trim());
    final otherCost = double.tryParse(_otherCampaignCost.text.trim());
    final attributionDays = int.tryParse(_attributionWindowDays.text.trim());
    if (smsCost == null || otherCost == null || smsCost < 0 || otherCost < 0) {
      _toast('هزینه‌ها باید عدد معتبر و غیرمنفی باشند.');
      return;
    }
    if (attributionDays == null || attributionDays < 1 || attributionDays > 90) {
      _toast('پنجره انتساب باید بین ۱ تا ۹۰ روز باشد.');
      return;
    }
    final confirmed = await _confirm(
      'ایجاد کمپین پیامکی',
      'برای ${_selectedCustomers.length} مشتری دارای رضایت، پیامک در صف قرار می‌گیرد. ارسال با تنظیمات فعلی و پس از تأیید اطلاعات درگاه انجام می‌شود. ادامه می‌دهید؟',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await _repo.createCampaign(
        name: _campaignName.text.trim(),
        customerIds: _selectedCustomers.toList(),
        message: _campaignMessage.text,
        bodyId: _campaignBodyId.text.trim(),
        patternArgs: _campaignPatternArgs.text
            .split(';')
            .map((e) => e.trim())
            .toList(),
        discountId: _selectedDiscountId,
        smsCostPerMessage: smsCost,
        otherCampaignCost: otherCost,
        attributionWindowDays: attributionDays,
      );
      _toast(
        'کمپین در صف قرار گرفت؛ تعداد گیرندگان: ${result['recipient_count'] ?? 0}.',
      );
      _selectedCustomers.clear();
      await _reloadLogs();
    } catch (e) {
      _toast('ساخت کمپین ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _queueTestSms() async {
    if (_testPhone.text.trim().isEmpty) {
      _toast('شماره موبایل آزمایشی را وارد کنید.');
      return;
    }
    if (!_isPattern && _testMessage.text.trim().isEmpty) {
      _toast('متن پیام آزمایشی را وارد کنید.');
      return;
    }
    final confirmed = await _confirm(
      'ثبت پیامک آزمایشی',
      'این پیام بعد از فعال‌سازی درگاه واقعی از اعتبار پنل پیامکی استفاده می‌کند. پیام آزمایشی در صف ارسال ثبت شود؟',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final id = await _repo.queueTestSms(
        phone: _testPhone.text,
        message: _testMessage.text,
        bodyId: _testBodyId.text.trim(),
        patternArgs: _testPatternArgs.text
            .split(';')
            .map((e) => e.trim())
            .toList(),
      );
      _toast('پیام آزمایشی با شناسه $id در صف قرار گرفت.');
      await _reloadLogs();
    } catch (e) {
      _toast('ثبت پیام آزمایشی ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _dispatchNow() async {
    final confirmed = await _confirm(
      'پردازش صف پیامک',
      'حداکثر ۲۰ پیامک قدیمی صف برای ارسال به درگاه ملی پیامک انتخاب می‌شوند. ارسال واقعی انجام شود؟',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await _repo.dispatch(batchSize: 20);
      _toast(
        'پردازش پایان یافت: ارسال ${result['sent'] ?? 0}، تلاش مجدد ${result['retried'] ?? 0}، ناموفق ${result['failed'] ?? 0}.',
      );
      await _reloadLogs();
    } catch (e) {
      _toast('پردازش صف انجام نشد: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadStaff() async {
    setState(() => _loadingStaff = true);
    try {
      _staff = await _repo.getStaff();
    } catch (e) {
      _toast('دریافت پرسنل ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  Future<void> _showStaffDialog({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(
      text: (existing?['name'] ?? '').toString(),
    );
    final phone = TextEditingController(
      text: (existing?['phone'] ?? '').toString(),
    );
    final role = TextEditingController(
      text: (existing?['role_label'] ?? 'پرسنل').toString(),
    );
    final currentTypes =
        (existing?['order_types'] as List? ??
                const ['delivery', 'pickup', 'dine_in'])
            .map((e) => e.toString())
            .toSet();
    var chosenTypes = Set<String>.from(currentTypes);
    var active = existing?['is_active'] != false;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'افزودن پرسنل دریافت پیامک' : 'ویرایش پرسنل',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'نام پرسنل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'شماره موبایل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: role,
                    decoration: const InputDecoration(
                      labelText: 'نقش (مثلاً گارسون / آشپز / ارسال)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('کدام نوع سفارش‌ها برای این پرسنل پیامک شود؟'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: chosenTypes.contains('delivery'),
                    title: const Text('ارسال به آدرس'),
                    onChanged: (v) => setDialogState(
                      () => v == true
                          ? chosenTypes.add('delivery')
                          : chosenTypes.remove('delivery'),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: chosenTypes.contains('pickup'),
                    title: const Text('دریافت حضوری'),
                    onChanged: (v) => setDialogState(
                      () => v == true
                          ? chosenTypes.add('pickup')
                          : chosenTypes.remove('pickup'),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: chosenTypes.contains('dine_in'),
                    title: const Text('سفارش داخل سالن'),
                    onChanged: (v) => setDialogState(
                      () => v == true
                          ? chosenTypes.add('dine_in')
                          : chosenTypes.remove('dine_in'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    title: const Text('دریافت پیامک فعال باشد'),
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    phone.text.trim().isEmpty ||
                    chosenTypes.isEmpty) {
                  return;
                }
                Navigator.pop(ctx, {
                  'name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'role': role.text.trim(),
                  'types': chosenTypes.toList(),
                  'active': active,
                });
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    role.dispose();
    if (payload == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repo.saveStaff(
        id: existing?['id']?.toString(),
        name: payload['name'] as String,
        phone: payload['phone'] as String,
        roleLabel: payload['role'] as String,
        orderTypes: List<String>.from(payload['types'] as List),
        active: payload['active'] as bool,
      );
      await _loadStaff();
      _toast('اطلاعات پرسنل ذخیره شد.');
    } catch (e) {
      _toast('ذخیره پرسنل ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStaffActive(Map<String, dynamic> member, bool active) async {
    try {
      await _repo.setStaffActive(member['id'].toString(), active);
      await _loadStaff();
    } catch (e) {
      _toast('تغییر وضعیت پرسنل ناموفق بود: $e');
    }
  }

  Future<void> _reloadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final values = await Future.wait<dynamic>([
        _repo.getOutbox(),
        _repo.getAttemptLogs(),
        _repo.getDeliveryStats(),
      ]);
      if (!mounted) return;
      _outbox = List<Map<String, dynamic>>.from(values[0] as List);
      _attempts = List<Map<String, dynamic>>.from(values[1] as List);
      _stats = List<Map<String, dynamic>>.from(values[2] as List);
    } catch (e) {
      _toast('بارگذاری گزارش پیامک ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأیید'),
            ),
          ],
        ),
      ) ??
      false;

  void _toast(String text) {
    if (!mounted) return;
    final safeMessage = AppErrorMessage.forDisplay(
      text,
      fallback: 'عملیات مرکز پیامک با مشکل روبه‌رو شد. تنظیمات و اتصال را بررسی کنید.',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(safeMessage)),
    );
  }

  String _eventTitle(String value) => switch (value) {
    'order_ready_customer' => 'آماده شدن سفارش مشتری',
    'ticket_received_customer' => 'ثبت تیکت مشتری',
    'ticket_answered_customer' => 'پاسخ تیکت',
    'ticket_new_message_admin' => 'اطلاع تیکت به مدیر',
    'new_order_staff' => 'سفارش جدید پرسنل',
    'marketing_campaign' => 'کمپین تبلیغاتی',
    'admin_test' => 'پیامک آزمایشی',
    _ => 'رویداد پیامکی دیگر',
  };

  String _statusTitle(String status) => switch (status) {
    'sent' => 'موفق',
    'failed' => 'ناموفق',
    'retry' => 'در انتظار تلاش مجدد',
    'queued' => 'در صف',
    'sending' => 'در حال ارسال',
    'cancelled' => 'لغو شده',
    _ => 'نامشخص',
  };

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _formatTimestamp(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'زمان نامشخص';
    final date = parsed.toLocal();
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
  }

  String _maskPhone(String phone) {
    final s = phone.trim();
    if (s.length < 7) return s;
    return '${s.substring(0, 3)}••••${s.substring(s.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sms_failed_outlined, size: 44),
              const SizedBox(height: 12),
              Text(
                'بارگذاری مرکز پیامک ناموفق بود:\n$_loadError',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              const Icon(Icons.sms_outlined, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرکز پیامک و بازاریابی',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _settings['provider_key_configured'] == true
                          ? 'کلید دسترسی در خزانهٔ امن ثبت شده است.'
                          : 'درگاه هنوز تنظیم نشده؛ پیامک واقعی ارسال نمی‌شود.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _settings['provider_key_configured'] == true
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'به‌روزرسانی همه اطلاعات',
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(
                icon: Icon(Icons.settings_outlined),
                text: 'تنظیمات و الگوها',
              ),
              Tab(icon: Icon(Icons.campaign_outlined), text: 'کمپین تبلیغاتی'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'پرسنل'),
              Tab(icon: Icon(Icons.analytics_outlined), text: 'گزارش و رویدادها'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildSettingsTab(),
              _buildCampaignTab(),
              _buildStaffTab(),
              _buildLogsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );
  Widget _switch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> changed,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: _saving ? null : changed,
  );

  Widget _buildSettingsTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اتصال ملی پیامک',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'کلید دسترسی فقط هنگام ذخیره به سرور فرستاده می‌شود و در خزانهٔ امن نگهداری می‌شود؛ کلید ذخیره‌شده هرگز دوباره به رابط کاربری بازگردانده نمی‌شود.',
            ),
            const SizedBox(height: 14),
            _switch(
              'فعال‌سازی پیامک',
              'وقتی خاموش باشد، پیامک جدیدی وارد صف ارسال نمی‌شود.',
              _smsEnabled,
              (v) => setState(() => _smsEnabled = v),
            ),
            _switch(
              'فعال‌سازی بازاریابی پیامکی',
              'کمپین فقط برای مشتریانی که رضایت پیامک تبلیغاتی دارند ساخته می‌شود.',
              _marketingEnabled,
              (v) => setState(() => _marketingEnabled = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _isPattern ? 'pattern' : 'normal',
              decoration: const InputDecoration(
                labelText: 'نوع ارسال',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'normal',
                  child: Text('عادی؛ متن مستقیم'),
                ),
                DropdownMenuItem(
                  value: 'pattern',
                  child: Text('پترن / خط خدماتی اشتراکی'),
                ),
              ],
              onChanged: (v) => setState(() => _isPattern = v == 'pattern'),
            ),
            const SizedBox(height: 12),
            _field(_username, 'نام کاربری ملی پیامک'),
            const SizedBox(height: 12),
            _field(
              _apiKey,
              _settings['provider_key_configured'] == true
                  ? 'API Key جدید (برای حفظ کلید فعلی خالی بگذارید)'
                  : 'API Key / رمز وب‌سرویس',
              obscure: true,
            ),
            const SizedBox(height: 12),
            _field(_sender, 'شماره فرستنده (برای ارسال عادی)'),
            const SizedBox(height: 12),
            _field(_defaultBodyId, 'Body ID پیش‌فرض (برای پترن)'),
            const SizedBox(height: 12),
            _field(
              _adminPhone,
              'شماره مدیر برای هشدار تیکت‌ها',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _maxAttempts,
                    'حداکثر تلاش (۱ تا ۱۰)',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _retryDelay,
                    'فاصله تلاش (ثانیه)',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _switch(
              'اطلاع به مشتری پس از آماده شدن سفارش',
              'هنگامی که وضعیت سفارش به «آماده» تغییر کند.',
              _notifyReady,
              (v) => setState(() => _notifyReady = v),
            ),
            _switch(
              'اطلاع پیامکی به مشتری درباره تیکت',
              'ثبت تیکت و پاسخ مدیر.',
              _notifyTicketCustomer,
              (v) => setState(() => _notifyTicketCustomer = v),
            ),
            _switch(
              'اطلاع پیامکی به مدیر درباره تیکت',
              'ثبت تیکت یا پیام جدید مشتری.',
              _notifyTicketAdmin,
              (v) => setState(() => _notifyTicketAdmin = v),
            ),
            _switch(
              'اطلاع سفارش جدید به پرسنل',
              'براساس نوع سفارش تعریف‌شده برای هر پرسنل.',
              _notifyStaff,
              (v) => setState(() => _notifyStaff = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveSettings,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('ذخیره تنظیمات امن'),
              ),
            ),
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ارسال پیامک آزمایشی',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'تست واقعی از اعتبار پنل پیامکی استفاده می‌کند؛ پیش از تأیید، شماره را دوباره بررسی کنید.',
            ),
            const SizedBox(height: 12),
            _field(
              _testPhone,
              'شماره گیرنده',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            if (!_isPattern)
              _field(_testMessage, 'متن پیام', maxLines: 3)
            else ...[
              _field(_testBodyId, 'Body ID الگو'),
              const SizedBox(height: 12),
              _field(_testPatternArgs, 'مقادیر متغیرهای الگو با ; جدا شوند'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _queueTestSms,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('ثبت پیام آزمایشی در صف'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _dispatchNow,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('پردازش صف اکنون'),
                ),
              ],
            ),
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الگوهای رویدادهای خودکار',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _saveTemplates,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('ذخیره الگوها'),
                ),
              ],
            ),
            const Text(
              'برای ارسال پیامک الگومحور، شناسهٔ الگوی هر رویداد را مطابق الگوی ثبت‌شده در پنل ملی پیامک وارد کنید. ترتیب مقدارهای متغیر باید با ترتیب پارامترهای الگو یکسان باشد.',
            ),
            const SizedBox(height: 12),
            ..._templates.map((template) {
              final key = template['event_key'].toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    (template['title'] ?? _eventTitle(key)).toString(),
                  ),
                  subtitle: Text(key),
                  trailing: Switch(
                    value: _templateActive[key] ?? true,
                    onChanged: (v) => setState(() => _templateActive[key] = v),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _field(
                        _normalTemplateControllers[key]!,
                        'متن ارسال عادی',
                        maxLines: 3,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _field(
                        _patternTemplateControllers[key]!,
                        'Body ID مخصوص این رویداد (اختیاری)',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'متغیرها: ${(template['param_keys'] as List? ?? const []).join('، ')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_templates.isEmpty)
              const Text('هنوز الگویی در دیتابیس ثبت نشده است.'),
          ],
        ),
      ),
    ],
  );

  Widget _buildCampaignTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'کمپین تبلیغاتی هدفمند',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text('${_selectedCustomers.length} انتخاب شده'),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'فقط مشتری فعال با شماره معتبر و رضایت ثبت‌شده انتخاب می‌شود. رضایت‌ها از اطلاعات مشتریان مدیریت می‌شوند؛ شماره بدون رضایت برای بازاریابی صف نمی‌شود.',
            ),
            if (!_marketingEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'بازاریابی پیامکی در تنظیمات خاموش است.',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 12),
            _field(_campaignName, 'نام کمپین'),
            const SizedBox(height: 12),
            if (!_isPattern)
              _field(_campaignMessage, 'متن پیامک', maxLines: 4)
            else ...[
              _field(_campaignBodyId, 'Body ID الگو'),
              const SizedBox(height: 12),
              _field(
                _campaignPatternArgs,
                'مقادیر متغیر ثابت با ; جدا شوند؛ برای نام/تلفن از {{name}} و {{phone}} استفاده کنید',
                maxLines: 2,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _selectedDiscountId,
              decoration: const InputDecoration(
                labelText: 'کد تخفیف متصل به کمپین (اختیاری)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('بدون کد تخفیف')),
                ..._activeDiscounts.map((d) => DropdownMenuItem<String?>(
                  value: d['id'].toString(),
                  child: Text('${d['title']} · ${d['code']}'),
                )),
              ],
              onChanged: (value) => setState(() => _selectedDiscountId = value),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_smsCostPerMessage, 'هزینه هر پیامک (تومان)', keyboardType: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: _field(_otherCampaignCost, 'هزینه جانبی کمپین (تومان)', keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 10),
            _field(_attributionWindowDays, 'پنجره انتساب خرید (روز؛ ۱ تا ۹۰)', keyboardType: TextInputType.number),
            const SizedBox(height: 5),
            const Text('برای پیامک عادی لینک رهگیری به انتهای متن افزوده می‌شود. در الگوی پترن باید متغیر {{track_url}} را در قالب و آرگومان‌ها پیش‌بینی کنید. هزینه هر پیامک را مطابق صورتحساب/تعرفه واقعی وارد کنید.',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _loadingCustomers
                      ? null
                      : () => _loadMarketingCustomers(
                          query: _customerSearch.text,
                        ),
                  icon: const Icon(Icons.search),
                  label: const Text('جست‌وجو'),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedCustomers.clear()),
                  child: const Text('لغو انتخاب همه'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedCustomers.addAll(
                      _eligibleCustomers.map((e) => e['id'].toString()),
                    );
                  }),
                  child: const Text('انتخاب فهرست جاری'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _field(_customerSearch, 'فیلتر نام یا شماره مشتری'),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('مشتریان دارای رضایت: ${_eligibleCustomers.length}'),
                const Spacer(),
                IconButton(
                  onPressed: _loadingCustomers
                      ? null
                      : () => _loadMarketingCustomers(
                          query: _customerSearch.text,
                        ),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loadingCustomers) const LinearProgressIndicator(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _eligibleCustomers.length,
                itemBuilder: (context, index) {
                  final customer = _eligibleCustomers[index];
                  final id = customer['id'].toString();
                  final name =
                      '${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''}'
                          .trim();
                  return CheckboxListTile(
                    value: _selectedCustomers.contains(id),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _selectedCustomers.add(id)
                          : _selectedCustomers.remove(id),
                    ),
                    title: Text(
                      name.isEmpty ? 'مشتری ${id.substring(0, 8)}' : name,
                    ),
                    subtitle: Text(
                      (customer['phone'] ?? 'بدون شماره').toString(),
                    ),
                    dense: true,
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || !_marketingEnabled
                    ? null
                    : _queueCampaign,
                icon: const Icon(Icons.campaign_outlined),
                label: Text(
                  _saving
                      ? 'در حال ثبت…'
                      : 'ثبت کمپین و قرار دادن پیام‌ها در صف',
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildStaffTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'پرسنل و دریافت سفارش',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _showStaffDialog(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('افزودن پرسنل'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'پرسنل فقط برای نوع سفارش‌هایی پیامک می‌گیرند که برایشان انتخاب کرده‌اید. اگر سفارش در فرم جزئیات به شخص خاصی تخصیص داده نشود، به پرسنل فعال منطبق با نوع سفارش اعلام می‌شود.',
            ),
            const SizedBox(height: 12),
            if (_loadingStaff) const LinearProgressIndicator(),
            if (_staff.isEmpty && !_loadingStaff)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('پرسنلی ثبت نشده است.')),
              ),
            ..._staff.map((member) {
              final types = (member['order_types'] as List? ?? const [])
                  .map(
                    (e) => e == 'delivery'
                        ? 'ارسال'
                        : e == 'pickup'
                        ? 'حضوری'
                        : 'سالن',
                  )
                  .join('، ');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(
                    (member['is_active'] == true)
                        ? Icons.person_outline
                        : Icons.person_off_outlined,
                  ),
                ),
                title: Text((member['name'] ?? '').toString()),
                subtitle: Text(
                  '${member['phone'] ?? ''} • ${member['role_label'] ?? 'پرسنل'}\nانواع سفارش: $types',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') _showStaffDialog(existing: member);
                    if (action == 'toggle') {
                      _setStaffActive(member, member['is_active'] != true);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        member['is_active'] == true
                            ? 'غیرفعال کردن'
                            : 'فعال کردن',
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ],
  );

  Widget _buildLogsTab() => RefreshIndicator(
    onRefresh: _reloadLogs,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric(
              'کل پیام‌ها',
              _outbox.length.toString(),
              Icons.sms_outlined,
            ),
            _metric(
              'موفق',
              _outbox.where((e) => e['status'] == 'sent').length.toString(),
              Icons.check_circle_outline,
              AppColors.success,
            ),
            _metric(
              'ناموفق',
              _outbox.where((e) => e['status'] == 'failed').length.toString(),
              Icons.error_outline,
              AppColors.error,
            ),
            _metric(
              'در صف/تلاش مجدد',
              _outbox
                  .where(
                    (e) =>
                        e['status'] == 'queued' ||
                        e['status'] == 'retry' ||
                        e['status'] == 'sending',
                  )
                  .length
                  .toString(),
              Icons.schedule,
              AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'نمودار وضعیت ارسال در ۷ روز اخیر',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(height: 240, child: _buildChart()),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  _legend(AppColors.success, 'موفق'),
                  _legend(AppColors.error, 'ناموفق'),
                  _legend(AppColors.primary, 'در انتظار'),
                ],
              ),
            ],
          ),
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'لاگ ارسال پیامک',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _reloadLogs,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _logStatusFilter,
                      decoration: const InputDecoration(
                        labelText: 'فیلتر نتیجه',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('همه وضعیت‌ها'),
                        ),
                        DropdownMenuItem(value: 'sent', child: Text('موفق')),
                        DropdownMenuItem(
                          value: 'failed',
                          child: Text('ناموفق'),
                        ),
                        DropdownMenuItem(
                          value: 'retry',
                          child: Text('تلاش مجدد'),
                        ),
                        DropdownMenuItem(value: 'queued', child: Text('در صف')),
                        DropdownMenuItem(
                          value: 'sending',
                          child: Text('در حال ارسال'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _logStatusFilter = v ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      initialValue: _logEventFilter,
                      decoration: const InputDecoration(
                        labelText: 'فیلتر نوع پیام',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('همه دسته‌ها'),
                        ),
                        ..._outbox
                            .map((e) => e['event_key'].toString())
                            .toSet()
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(_eventTitle(e)),
                              ),
                            ),
                      ],
                      onChanged: (v) =>
                          setState(() => _logEventFilter = v ?? 'all'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loadingLogs) const LinearProgressIndicator(),
              if (_filteredOutbox.isEmpty && !_loadingLogs)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('هیچ رکورد پیامکی برای این فیلتر وجود ندارد.'),
                  ),
                ),
              ..._filteredOutbox.take(200).map((row) {
                final status = (row['status'] ?? '').toString();
                final statusColor = status == 'sent'
                    ? AppColors.success
                    : status == 'failed'
                    ? AppColors.error
                    : AppColors.primary;
                return ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: Icon(
                    status == 'sent'
                        ? Icons.check_circle
                        : status == 'failed'
                        ? Icons.error_outline
                        : Icons.schedule,
                    color: statusColor,
                  ),
                  title: Text(
                    '${_eventTitle((row['event_key'] ?? '').toString())} • ${_maskPhone((row['recipient_phone'] ?? '').toString())}',
                  ),
                  subtitle: Text(
                    '${_statusTitle(status)} • تلاش ${_persianDigits(row['attempts'] ?? 0)}/${_persianDigits(row['max_attempts'] ?? 5)} • ${_formatTimestamp(row['created_at'])}',
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('شناسه: ${(row['id'] ?? '').toString()}'),
                    ),
                    if ((row['provider_message_id'] ?? '')
                        .toString()
                        .isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'شناسه درگاه: ${row['provider_message_id']}',
                        ),
                      ),
                    if ((row['last_error'] ?? '').toString().isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          AppErrorMessage.forDisplay((row['last_error'] ?? '').toString(), fallback: 'ارسال پیامک ناموفق بود. وضعیت صف پیامک را بررسی کنید.'),
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    if ((row['normal_message'] ?? '').toString().isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          (row['normal_message']).toString(),
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تلاش‌های هر پیام',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '${_attempts.length} تلاش اخیر از جدول لاگ مستقل خوانده شده‌اند.',
              ),
              if (_attempts.isNotEmpty)
                ..._attempts
                    .take(20)
                    .map(
                      (a) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          a['success'] == true
                              ? Icons.check_circle
                              : Icons.cancel_outlined,
                          color: a['success'] == true
                              ? AppColors.success
                              : AppColors.error,
                        ),
                        title: Text(
                          'تلاش ${_persianDigits(a['attempt_no'])} • ${_persianDigits(a['response_code'] ?? 'بدون کد')}',
                        ),
                        subtitle: Text(
                          '${_formatTimestamp(a['created_at'])} • ${AppErrorMessage.forDisplay((a['error_message'] ?? 'بدون خطا').toString(), fallback: 'جزئیات خطای ارسال در دسترس نیست.')}',
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Map<String, dynamic>> get _filteredOutbox => _outbox
      .where((row) {
        final statusOk =
            _logStatusFilter == 'all' || row['status'] == _logStatusFilter;
        final eventOk =
            _logEventFilter == 'all' || row['event_key'] == _logEventFilter;
        return statusOk && eventOk;
      })
      .toList(growable: false);

  Widget _metric(String title, String value, IconData icon, [Color? color]) =>
      SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: color ?? AppColors.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label),
    ],
  );

  Widget _buildChart() {
    final now = DateTime.now();
    final days = List<DateTime>.generate(
      7,
      (i) => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i)),
    );
    final rowsByDay = <String, Map<String, int>>{};
    for (final date in days) {
      rowsByDay[DateFormat('yyyy-MM-dd').format(date)] = {
        'sent': 0,
        'failed': 0,
        'pending': 0,
      };
    }
    for (final row in _stats) {
      final dateValue = (row['report_date'] ?? '').toString();
      final date = dateValue.length >= 10
          ? dateValue.substring(0, 10)
          : dateValue;
      final entry = rowsByDay[date];
      if (entry == null) continue;
      final count = (row['message_count'] as num? ?? 0).toInt();
      final status = (row['status'] ?? '').toString();
      if (status == 'sent') {
        entry['sent'] = (entry['sent'] ?? 0) + count;
      } else if (status == 'failed') {
        entry['failed'] = (entry['failed'] ?? 0) + count;
      } else {
        entry['pending'] = (entry['pending'] ?? 0) + count;
      }
    }
    final maxValue = rowsByDay.values
        .expand((e) => e.values)
        .fold<int>(1, (p, c) => c > p ? c : p)
        .toDouble();
    return BarChart(
      BarChartData(
        maxY: maxValue * 1.25,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    DateFormat('MM/dd').format(days[i]),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(days.length, (i) {
          final key = DateFormat('yyyy-MM-dd').format(days[i]);
          final values = rowsByDay[key]!;
          return BarChartGroupData(
            x: i,
            barsSpace: 3,
            barRods: [
              BarChartRodData(
                toY: (values['sent'] ?? 0).toDouble(),
                width: 7,
                color: AppColors.success,
                borderRadius: BorderRadius.circular(3),
              ),
              BarChartRodData(
                toY: (values['failed'] ?? 0).toDouble(),
                width: 7,
                color: AppColors.error,
                borderRadius: BorderRadius.circular(3),
              ),
              BarChartRodData(
                toY: (values['pending'] ?? 0).toDouble(),
                width: 7,
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          );
        }),
      ),
    );
  }
}
