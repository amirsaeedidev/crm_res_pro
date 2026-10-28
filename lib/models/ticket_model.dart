class TicketMessageModel {
  final String id;
  final String ticketId;
  final String userId;
  final String message;
  final bool isAdmin;
  final DateTime createdAt;
  final String? senderName;

  const TicketMessageModel({required this.id, required this.ticketId, required this.userId,
    required this.message, required this.isAdmin, required this.createdAt, this.senderName});

  factory TicketMessageModel.fromJson(Map<String, dynamic> json, {String? senderName}) => TicketMessageModel(
    id: json['id'].toString(), ticketId: json['ticket_id'].toString(), userId: (json['user_id'] ?? '').toString(),
    message: (json['message'] ?? '').toString(), isAdmin: json['is_admin'] as bool? ?? false,
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    senderName: senderName);
}

class TicketModel {
  final String id;
  final String userId;
  final String subject;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? adminReadAt;
  final DateTime? customerReadAt;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final List<TicketMessageModel> messages;

  const TicketModel({required this.id, required this.userId, required this.subject,
    required this.status, required this.createdAt, this.updatedAt, this.adminReadAt, this.customerReadAt, this.customerName = '',
    this.customerPhone = '', this.customerEmail = '', this.messages = const []});

  factory TicketModel.fromJson(Map<String, dynamic> json, {String customerName = '', String customerPhone = '', String customerEmail = '', List<TicketMessageModel> messages = const []}) => TicketModel(
    id: json['id'].toString(), userId: (json['user_id'] ?? '').toString(),
    subject: (json['subject'] ?? '').toString(), status: (json['status'] ?? 'open').toString(),
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    adminReadAt: DateTime.tryParse((json['admin_read_at'] ?? '').toString()),
    customerReadAt: DateTime.tryParse((json['customer_read_at'] ?? '').toString()), customerName: customerName,
    customerPhone: customerPhone, customerEmail: customerEmail, messages: messages);

  bool get isUnread => status == 'open' && adminReadAt == null;

  TicketModel copyWith({String? status, List<TicketMessageModel>? messages, DateTime? adminReadAt}) => TicketModel(
    id: id, userId: userId, subject: subject, status: status ?? this.status,
    createdAt: createdAt, updatedAt: updatedAt, adminReadAt: adminReadAt ?? this.adminReadAt, customerReadAt: customerReadAt, customerName: customerName, customerPhone: customerPhone,
    customerEmail: customerEmail, messages: messages ?? this.messages);
}
