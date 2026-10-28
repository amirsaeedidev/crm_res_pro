class CategoryModel {
  final String id;
  final String name;
  /// Not stored by the current Supabase schema; retained only for source compatibility.
  final String? description;
  final String? imageUrl;
  final bool isActive;
  /// Maps to the real database column `sort_order`.
  final int displayOrder;
  final int loyaltyPointsPerItem;
  final DateTime createdAt;

  const CategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    this.isActive = true,
    this.displayOrder = 0,
    this.loyaltyPointsPerItem = 0,
    required this.createdAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        displayOrder: (json['sort_order'] ?? json['display_order'] ?? 0) as int,
        loyaltyPointsPerItem: (json['loyalty_points_per_item'] ?? 0) as int,
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// Serializes only columns that exist in public.categories.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image_url': imageUrl,
        'sort_order': displayOrder,
        'is_active': isActive,
        'loyalty_points_per_item': loyaltyPointsPerItem,
        'created_at': createdAt.toIso8601String(),
      };

  CategoryModel copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    bool? isActive,
    int? displayOrder,
    int? loyaltyPointsPerItem,
    DateTime? createdAt,
  }) => CategoryModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        isActive: isActive ?? this.isActive,
        displayOrder: displayOrder ?? this.displayOrder,
        loyaltyPointsPerItem: loyaltyPointsPerItem ?? this.loyaltyPointsPerItem,
        createdAt: createdAt ?? this.createdAt,
      );
}
