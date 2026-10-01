import 'package:flutter/material.dart';

import '../../../catalog/models/product.dart';

/// A product image with a neutral placeholder while unresolved, when there
/// is no image, or when it fails to load (MA-145 FR-7).
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.product, this.size = 56, this.circle = false});

  final Product? product;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.local_grocery_store_outlined, size: size * 0.45, color: scheme.outline),
    );
    final url = product?.imageUrl;
    final image = (url == null || url.isEmpty)
        ? placeholder
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );
    return ExcludeSemantics(
      child: circle
          ? ClipOval(child: image)
          : ClipRRect(borderRadius: BorderRadius.circular(size * 0.3), child: image),
    );
  }
}

/// MA-145 FR-7: "…" while the lookup is pending (no key yet), "Item" when
/// it failed (key mapped to null), else the product's name.
String productNameFor(Map<String, Product?> products, String productId) {
  if (!products.containsKey(productId)) return '…';
  return products[productId]?.name ?? 'Item';
}
