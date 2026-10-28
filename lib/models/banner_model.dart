class BannerModel {
  final String id;
  final String title;
  final String? subtitle;
  final String? promoTitle;
  final String? discountCode;
  final String? logoUrl;
  final String? emoji; // Not stored in the current schema.
  final String? imageUrl;
  final String? actionUrl; // Not stored in the current schema.
  final bool isActive;
  final bool isDeleted; // No soft-delete column exists; deletions are hard deletes.
  final int displayOrder;
  final DateTime startDate; // Alias of created_at for old UI compatibility.
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BannerModel({required this.id, required this.title, this.subtitle, this.promoTitle, this.discountCode, this.logoUrl, this.emoji,
    this.imageUrl, this.actionUrl, this.isActive = true, this.isDeleted = false,
    this.displayOrder = 0, required this.startDate, this.endDate,
    required this.createdAt, this.updatedAt});

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return BannerModel(
      id: json['id'].toString(), title: (json['title'] ?? '').toString(),
      imageUrl: json['image_url'] as String?, subtitle: (json['subtitle'] ?? '').toString(),
      promoTitle: (json['promo_title'] ?? '').toString(), discountCode: json['discount_code']?.toString(),
      logoUrl: json['logo_url']?.toString(), isActive: json['is_active'] as bool? ?? true,
      displayOrder: (json['sort_order'] ?? json['display_order'] ?? 0) as int,
      startDate: created, createdAt: created,
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'image_url': imageUrl, 'sort_order': displayOrder,
    'subtitle': subtitle ?? '', 'promo_title': promoTitle ?? '', 'discount_code': discountCode, 'logo_url': logoUrl,
    'is_active': isActive, 'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  BannerModel copyWith({String? id, String? title, String? subtitle, String? promoTitle, String? discountCode, String? logoUrl, String? emoji,
    String? imageUrl, String? actionUrl, bool? isActive, bool? isDeleted,
    int? displayOrder, DateTime? startDate, DateTime? endDate,
    DateTime? createdAt, DateTime? updatedAt}) => BannerModel(
      id: id ?? this.id, title: title ?? this.title, subtitle: subtitle ?? this.subtitle,
      promoTitle: promoTitle ?? this.promoTitle, discountCode: discountCode ?? this.discountCode, logoUrl: logoUrl ?? this.logoUrl,
      emoji: emoji ?? this.emoji, imageUrl: imageUrl ?? this.imageUrl,
      actionUrl: actionUrl ?? this.actionUrl, isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted, displayOrder: displayOrder ?? this.displayOrder,
      startDate: startDate ?? this.startDate, endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt);
}
