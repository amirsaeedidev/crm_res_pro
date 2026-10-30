import 'package:flutter_test/flutter_test.dart';
import 'package:crm_panel/features/inventory/utils/inventory_unit_converter.dart';

void main() {
  group('InventoryUnitConverter', () {
    test('converts kilograms to grams and back', () {
      expect(InventoryUnitConverter.convertQuantity(quantity: 2, purchaseUnit: 'kg', stockUnit: 'g'), 2000);
      expect(InventoryUnitConverter.convertQuantity(quantity: 750, purchaseUnit: 'g', stockUnit: 'kg'), 0.75);
    });

    test('converts liters to milliliters and price per base unit', () {
      expect(InventoryUnitConverter.convertQuantity(quantity: 1.5, purchaseUnit: 'l', stockUnit: 'ml'), 1500);
      expect(InventoryUnitConverter.convertUnitCost(costPerPurchaseUnit: 120000, purchaseUnit: 'l', stockUnit: 'ml'), 120);
    });

    test('keeps same units unchanged', () {
      expect(InventoryUnitConverter.convertQuantity(quantity: 4, purchaseUnit: 'unit', stockUnit: 'unit'), 4);
      expect(InventoryUnitConverter.convertUnitCost(costPerPurchaseUnit: 2500, purchaseUnit: 'unit', stockUnit: 'unit'), 2500);
    });

    test('rejects incompatible units', () {
      expect(() => InventoryUnitConverter.quantityRatio(purchaseUnit: 'kg', stockUnit: 'ml'), throwsArgumentError);
      expect(InventoryUnitConverter.areCompatible('pack', 'box'), isFalse);
    });

    test('converts bulk purchase quantity and unit price without changing invoice total', () {
      final stockQuantity = InventoryUnitConverter.convertQuantity(
        quantity: 3,
        purchaseUnit: 'kg',
        stockUnit: 'g',
      );
      final stockUnitCost = InventoryUnitConverter.convertUnitCost(
        costPerPurchaseUnit: 180000,
        purchaseUnit: 'kg',
        stockUnit: 'g',
      );
      expect(stockQuantity, 3000);
      expect(stockUnitCost, 60);
      expect(stockQuantity * stockUnitCost, 180000);
    });

    test('keeps volume and mass conversions separate', () {
      expect(InventoryUnitConverter.areCompatible('kg', 'l'), isFalse);
      expect(InventoryUnitConverter.areCompatible('ml', 'g'), isFalse);
    });

    test('parses Persian and Arabic numerals', () {
      expect(InventoryUnitConverter.parseLocalizedNumber('۱٬۲۵۰٫۵'), 1250.5);
      expect(InventoryUnitConverter.parseLocalizedNumber('١٢٣٫٧'), 123.7);
      expect(InventoryUnitConverter.parseLocalizedNumber('نامعتبر'), isNull);
    });
  });
}
