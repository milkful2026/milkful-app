/// Money helpers. The backend is integer paise everywhere; Catalog's
/// `Product.price` is the one rupee-denominated (decimal) input, converted
/// with [rupeesToPaise] at the point it's read so no rupee value reaches
/// arithmetic or formatting.
library;

/// `₹65` when the paise part is zero, `₹65.50` otherwise. With
/// [alwaysDecimals], always two decimals (`₹65.00`) — the order detail
/// screen's bill uses that form.
String formatPaise(int paise, {bool alwaysDecimals = false}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final rest = abs % 100;
  final body = (alwaysDecimals || rest != 0)
      ? '$rupees.${rest.toString().padLeft(2, '0')}'
      : '$rupees';
  return '${negative ? '-' : ''}₹$body';
}

/// Rounds to whole paise. Round a *unit* price before multiplying by a
/// quantity, so a total is always a whole number of paise.
int rupeesToPaise(double rupees) => (rupees * 100).round();
