import 'package:flutter/material.dart';

/// Shared "Fresh from the Farm" promo banner — used on both Home's landing
/// page (search → banner → categories) and the full catalog page at
/// `/catalog` (search → banner → category rail), keeping the same visual
/// and ordering in both places.
class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key, required this.onShopNow});

  final VoidCallback onShopNow;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [primary, primary.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              'Fresh from the Farm',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Delivered within 24 hours of milking.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('promo-banner-shop-now'),
              onPressed: onShopNow,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Shop Now'),
            ),
          ],
        ),
      ),
    );
  }
}
