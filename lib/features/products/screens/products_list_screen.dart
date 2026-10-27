import 'package:cached_network_image/cached_network_image.dart';
import 'package:crm_panel/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/app_search.dart';
import '../../../core/widgets/custom_chip.dart';
import '../../../models/product_model.dart';
import '../../../providers/products_provider.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;
import '../../../shared/widgets/pagination_widget.dart';

class ProductsListScreen extends StatefulWidget {
  const ProductsListScreen({super.key});

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends State<ProductsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('en_US');
  final Set<String> _togglingProductIds = <String>{};

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _priceLabel(num value) => '${_persianDigits(
        _currencyFormatter.format(value).replaceAll(',', '٬'),
      )} تومان';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductsProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مدیریت محصولات',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.getPrimaryText(context),
                      fontWeight: FontWeight.bold,
                    ),
              ),
              AppButton(
                label: 'افزودن محصول جدید',
                icon: Icons.add_rounded,
                width: 200,
                onPressed: () {
                  context.push('/products/add');
                },
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),

          // Search Bar
          AppSearch(
            controller: _searchController,
            onChanged: (value) {
              context.read<ProductsProvider>().setSearchQuery(value);
            },
          ),
          const SizedBox(height: AppSizes.lg),

          // Content Area
          Expanded(
            child: Consumer<ProductsProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.products.isEmpty) {
                  return const Center(child: AppLoading());
                }

                if (provider.error != null && provider.products.isEmpty) {
                  return app_error.AppErrorWidget(
                    message: provider.error!,
                    onRetry: () => provider.fetchProducts(),
                  );
                }

                if (provider.products.isEmpty) {
                  return const EmptyWidget(
                    title: 'محصولی پیدا نشد',
                    message: 'محصولی با این مشخصات پیدا نشد.',
                    icon: Icons.inventory_2_outlined,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    // Desktop & Tablet: Table View
                    if (constraints.maxWidth > 600) {
                      return _buildDesktopTable(context, provider);
                    }
                    // Mobile: Card View
                    return _buildMobileList(context, provider);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(BuildContext context, ProductsProvider provider) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.medium),
                topRight: Radius.circular(AppRadius.medium),
              ),
            ),
            child: Row(
              children: [
                _buildHeaderText(context, 'محصول', 3),
                _buildHeaderText(context, 'قیمت', 2),
                _buildHeaderText(context, 'امتیاز', 1),
                _buildHeaderText(context, 'وضعیت', 1),
                _buildHeaderText(context, 'عملیات', 1),
              ],
            ),
          ),
          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: provider.products.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Theme.of(context).dividerColor,
              ),
              itemBuilder: (context, index) {
                final product = provider.products[index];
                return _buildDesktopRow(context, provider, product);
              },
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
  }

  Widget _buildHeaderText(BuildContext context, String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildDesktopRow(BuildContext context, ProductsProvider provider, ProductModel product) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
      child: Row(
        children: [
          // Product Name & Category
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (product.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      placeholder: (_, _) => const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )),
                      ),
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.broken_image, size: 40),
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.getBackground(context),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Icon(Icons.image_outlined, color: AppColors.getSecondaryText(context)),
                  ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            product.name,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (product.isPopular) ...[
                            const SizedBox(width: AppSizes.sm),
                            const CustomChip(label: 'محبوب', type: ChipType.primary),
                          ]
                        ],
                      ),
                      Text(
                        (product.categoryName?.isNotEmpty == true ? product.categoryName! : 'بدون دسته‌بندی'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.getSecondaryText(context),
                            ),
                      ),
                      if (product.labels.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: product.labels.take(4).map((label) => CustomChip(label: label, type: ChipType.neutral)).toList()),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Price
          Expanded(
            flex: 2,
            child: _buildPriceWidget(context, product),
          ),
          
          // Rating
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Icon(Icons.star, size: 16, color: Colors.amber[700]),
                const SizedBox(width: 4),
                Text(
                  product.rating != null 
                      ? '${product.rating!.toStringAsFixed(1)} (${product.reviewCount ?? 0})'
                      : 'N/A',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          
          // Status Toggle
          Expanded(
            flex: 1,
            child: _buildStatusToggle(context, provider, product),
          ),
          
          // Actions
          Expanded(
            flex: 1,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility_outlined, color: AppColors.info),
                  onPressed: () {
                    context.push('/products/details/${product.id}');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                  onPressed: () {
                    context.push('/products/edit/${product.id}');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () {
                    DeleteDialog.show(
                      context: context,
                      title: 'حذف محصول',
                      message: 'آیا از حذف محصول «${product.name}» مطمئن هستید؟',
                      onDelete: () {
                        provider.deleteProduct(product.id);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(BuildContext context, ProductsProvider provider) {
    return ListView.separated(
      itemCount: provider.products.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSizes.md),
      itemBuilder: (context, index) {
        final product = provider.products[index];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        placeholder: (_, _) => const SizedBox(
                          width: 60,
                          height: 60,
                          child: Center(child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )),
                        ),
                        errorWidget: (_, _, _) =>
                            const Icon(Icons.broken_image, size: 60),
                      ),
                    )
                  else
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.getBackground(context),
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: Icon(Icons.image_outlined, color: AppColors.getSecondaryText(context)),
                    ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (product.isPopular)
                              const CustomChip(label: 'محبوب', type: ChipType.primary),
                          ],
                        ),
                        if (product.labels.isNotEmpty) ...[
                          const SizedBox(height: AppSizes.xs),
                          Wrap(spacing: 4, runSpacing: 4, children: product.labels.take(4).map((label) => CustomChip(label: label, type: ChipType.neutral)).toList()),
                        ],
                        const SizedBox(height: AppSizes.xs),
                        _buildPriceWidget(context, product),
                        const SizedBox(height: AppSizes.xs),
                        Row(
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.amber[700]),
                            const SizedBox(width: 4),
                            Text(
                              product.rating != null 
                                  ? '${product.rating!.toStringAsFixed(1)} (${product.reviewCount ?? 0})'
                                  : 'N/A',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: AppSizes.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatusToggle(context, provider, product),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, color: AppColors.info),
                        onPressed: () {
                          context.push('/products/details/${product.id}');
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                        onPressed: () {
                          context.push('/products/edit/${product.id}');
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () {
                          DeleteDialog.show(
                            context: context,
                            title: 'حذف محصول',
                            message: 'آیا از حذف محصول «${product.name}» مطمئن هستید؟',
                            onDelete: () {
                              provider.deleteProduct(product.id);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildPriceWidget(BuildContext context, ProductModel product) {
    if (product.discountedPrice != null && product.discountedPrice! < product.price) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _priceLabel(product.price),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: AppColors.getSecondaryText(context),
                ),
          ),
          Text(
            _priceLabel(product.discountedPrice!),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
          ),
        ],
      );
    }
    
    return Text(
      _priceLabel(product.price),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildStatusToggle(BuildContext context, ProductsProvider provider, ProductModel product) {
    final isToggling = _togglingProductIds.contains(product.id);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: product.status == 'active',
          onChanged: isToggling
              ? null
              : (enabled) async {
                  setState(() => _togglingProductIds.add(product.id));
                  final success = await provider.toggleProductStatus(product.id, enabled);
                  if (!context.mounted) return;
                  setState(() => _togglingProductIds.remove(product.id));
                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(provider.error ?? 'تغییر وضعیت محصول ذخیره نشد.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
          activeThumbColor: AppColors.success,
        ),
        if (isToggling)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Text(
            product.status == 'active' ? 'Available' : 'Unavailable',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: product.status == 'active' ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
          ),
      ],
    );
  }
}