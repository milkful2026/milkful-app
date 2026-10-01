import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/utils/ist_clock.dart';
import 'package:milkful_app/core/utils/money.dart';

void main() {
  group('formatPaise', () {
    test('drops .00 for whole rupees, keeps paise otherwise', () {
      expect(formatPaise(6500), '₹65');
      expect(formatPaise(6550), '₹65.50');
      expect(formatPaise(5), '₹0.05');
    });

    test('alwaysDecimals', () {
      expect(formatPaise(6500, alwaysDecimals: true), '₹65.00');
      expect(formatPaise(15500, alwaysDecimals: true), '₹155.00');
    });
  });

  group('rupeesToPaise', () {
    test('rounds a rupee price to whole paise', () {
      expect(rupeesToPaise(32.5), 3250);
      expect(rupeesToPaise(32.49), 3249);
      expect(rupeesToPaise(37.485), 3749);
    });
  });

  group('istToday', () {
    test('18:29:59 UTC is still the same IST date', () {
      expect(istToday(() => DateTime.utc(2026, 10, 1, 18, 29, 59)), DateTime(2026, 10, 1));
    });

    test('18:30:00 UTC is the next IST date', () {
      expect(istToday(() => DateTime.utc(2026, 10, 1, 18, 30)), DateTime(2026, 10, 2));
    });
  });

  test('parseApiDate ignores any time suffix', () {
    expect(parseApiDate('2026-10-03'), DateTime(2026, 10, 3));
    expect(parseApiDate('2026-10-03T00:00:00+05:30'), DateTime(2026, 10, 3));
  });
}
