import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bloc/inventory/inventory_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../models/product_variant.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Master Inventory',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (user.isAdminOrOwner)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showCategoriesDialog(context),
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('Manage Categories'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Product'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<InventoryCubit, List<Product>>(
              builder: (context, products) {
                return FutureBuilder<List<Category>>(
                  future: context.read<InventoryCubit>().categories(),
                  builder: (context, categorySnap) {
                    final categories = categorySnap.data ?? const <Category>[];
                    final categoryNameById = {
                      for (final category in categories) category.id: category.name,
                    };

                    return RefreshIndicator(
                      onRefresh: () async {
                        await context.read<InventoryCubit>().load();
                      },
                      child: ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, i) {
                          final p = products[i];
                          final categoryName =
                              categoryNameById[p.categoryId] ?? 'Uncategorized';
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.inventory_2_outlined),
                              ),
                              title: Text(p.name),
                              subtitle: Text(
                                '$categoryName • PHP ${p.basePrice.toStringAsFixed(2)} • Stock ${p.stockQuantity}',
                              ),
                              trailing: user.isAdminOrOwner
                                  ? Wrap(
                                      spacing: 8,
                                      children: [
                                        IconButton(
                                          onPressed: () => _showProductDialog(
                                            context,
                                            product: p,
                                          ),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          onPressed: () async {
                                            final confirmed = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    title: const Text('Delete Product'),
                                                    content: Text(
                                                      'Delete "${p.name}"?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context, false),
                                                        style: TextButton.styleFrom(
                                                          backgroundColor: Colors.white,
                                                          foregroundColor: AppColors.primary,
                                                          side: BorderSide(color: AppColors.primary),
                                                        ),
                                                        child: const Text('Cancel'),
                                                      ),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: const Color(0xFFFF5252),
                                                          foregroundColor: Colors.white,
                                                        ),
                                                        onPressed: () => Navigator.pop(context, true),
                                                        child: const Text('Delete'),
                                                      ),
                                                    ],
                                                  ),
                                                ) ??
                                                false;
                                            if (confirmed && context.mounted) {
                                              await context
                                                  .read<InventoryCubit>()
                                                  .delete(p.id);
                                            }
                                          },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Color(0xFFFF5252),
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    await _showProductDialog(context);
  }

  Future<void> _showProductDialog(BuildContext context, {Product? product}) async {
    final cubit = context.read<InventoryCubit>();
    var categories = await cubit.categories();
    final initialCategoryId = product?.categoryId ??
        (categories.isNotEmpty ? categories.first.id : null);

    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(
      text: product == null ? '' : product.basePrice.toStringAsFixed(2),
    );
    final stockQuantityController = TextEditingController(
      text: product == null ? '' : product.stockQuantity.toString(),
    );
    String? imagePath = product?.imagePath;
    int? selectedCategoryId = initialCategoryId;
    bool hasVariants = false;
    String groupName = '';
    final options = <_VariantOptionInput>[];

    if (product != null) {
      final group = await cubit.variantGroupForProduct(product.id);
      final variantOptions = await cubit.variantOptionsForProduct(product.id);
      hasVariants = group != null;
      groupName = group?.name ?? '';
      options.addAll(
        variantOptions
            .map(
              (option) => _VariantOptionInput(
                value: option.value,
                extraPrice: option.extraPrice.toString(),
              ),
            )
            .toList(),
      );
    }

    if (options.isEmpty) {
      options.add(_VariantOptionInput());
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> addCategoryInline() async {
              final name = TextEditingController();
              final description = TextEditingController();
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  title: const Text('Add Category'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category name',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: name,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          filled: true,
                          fillColor: const Color(0xFFF5F1FB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Description (optional)',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: description,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          filled: true,
                          fillColor: const Color(0xFFF5F1FB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      )
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final value = name.text.trim();
                        if (value.isEmpty) {
                          return;
                        }
                        final created = await cubit.addCategory(
                          name: value,
                          description: description.text,
                        );
                        categories = await cubit.categories();
                        selectedCategoryId = created.id;
                        if (context.mounted) {
                          Navigator.pop(context);
                          setState(() {});
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
            }

            Future<void> pickImage() async {
              final picker = ImagePicker();
              final file = await picker.pickImage(source: ImageSource.gallery);
              if (file != null) {
                setState(() {
                  imagePath = file.path;
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              title: Text(product == null ? 'Add Product' : 'Edit Product'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Category',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<int>(
                                  initialValue: selectedCategoryId,
                                  items: categories
                                      .map(
                                        (category) => DropdownMenuItem<int>(
                                          value: category.id,
                                          child: Text(category.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedCategoryId = value;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                    filled: true,
                                    fillColor: const Color(0xFFF5F1FB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: IconButton(
                              onPressed: addCategoryInline,
                              tooltip: 'Add new category',
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Product name',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          filled: true,
                          fillColor: const Color(0xFFF5F1FB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Base price',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: priceController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                    filled: true,
                                    fillColor: const Color(0xFFF5F1FB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stock quantity',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: stockQuantityController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                    filled: true,
                                    fillColor: const Color(0xFFF5F1FB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: pickImage,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          imagePath == null || imagePath!.isEmpty
                              ? 'Pick image'
                              : 'Change image',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('This product has variants'),
                        value: hasVariants,
                        onChanged: (value) {
                          setState(() {
                            hasVariants = value;
                          });
                        },
                      ),
                      if (hasVariants) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Variant group name (e.g., Size, Color)',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          initialValue: groupName,
                          onChanged: (value) => groupName = value,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            filled: true,
                            fillColor: const Color(0xFFF5F1FB),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(options.length, (index) {
                          final option = options[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Value',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextFormField(
                                            initialValue: option.value,
                                            onChanged: (value) => option.value = value,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                              filled: true,
                                              fillColor: const Color(0xFFF5F1FB),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Extra price',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextFormField(
                                            initialValue: option.extraPrice,
                                            onChanged: (value) => option.extraPrice = value,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                              filled: true,
                                              fillColor: const Color(0xFFF5F1FB),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8, top: 20),
                                      child: IconButton(
                                        onPressed: options.length <= 1
                                            ? null
                                            : () {
                                                setState(() {
                                                  options.removeAt(index);
                                                });
                                              },
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              options.add(_VariantOptionInput());
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add option'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final basePrice = double.tryParse(priceController.text.trim());

                    if (name.isEmpty || selectedCategoryId == null || basePrice == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Category, name, and valid base price are required.',
                          ),
                        ),
                      );
                      return;
                    }

                    final cleanOptions = options
                        .where((option) => option.value.trim().isNotEmpty)
                        .map(
                          (option) => ProductVariantOption(
                            id: 0,
                            variantGroupId: 0,
                            value: option.value.trim(),
                            extraPrice:
                                double.tryParse(option.extraPrice.trim()) ?? 0,
                          ),
                        )
                        .toList();

                    if (hasVariants && cleanOptions.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Add at least one variant option when variants are enabled.',
                          ),
                        ),
                      );
                      return;
                    }

                    await cubit.saveProduct(
                      id: product?.id,
                      name: name,
                      description: product?.description,
                      categoryId: selectedCategoryId!,
                      basePrice: basePrice,
                      imagePath: imagePath,
                      variantGroupName: hasVariants ? groupName.trim() : null,
                      variantOptions: hasVariants ? cleanOptions : const [],
                      stockQuantity: int.tryParse(stockQuantityController.text.trim()) ?? 0,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCategoriesDialog(BuildContext context) async {
    final cubit = context.read<InventoryCubit>();
    final categories = await cubit.categories();

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Text('Manage Categories'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  categories.length,
                  (index) {
                    final category = categories[index];
                    return ListTile(
                      title: Text(category.name),
                      subtitle: category.description != null
                          ? Text(category.description!)
                          : null,
                      trailing: IconButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              title: const Text('Delete Category'),
                              content: Text(
                                'Delete "${category.name}"? All products will be removed.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(color: Color(0xFFFF5252)),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4CAF50),
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                          if (confirmed && context.mounted) {
                            await cubit.deleteCategory(category.id);
                            if (context.mounted) {
                              _showCategoriesDialog(context);
                            }
                          }
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFFF5252),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _VariantOptionInput {
  _VariantOptionInput({this.value = '', this.extraPrice = '0'});

  String value;
  String extraPrice;
}
