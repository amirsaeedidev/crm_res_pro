/// Converts compatible purchase units into the material's stock unit.
class InventoryUnitConverter {
  InventoryUnitConverter._();

  static const Map<String, double> _baseFactor = {
    'g': 1,
    'kg': 1000,
    'ml': 1,
    'l': 1000,
    'unit': 1,
    'pack': 1,
    'box': 1,
  };

  static bool areCompatible(String from, String to) {
    if (!_baseFactor.containsKey(from) || !_baseFactor.containsKey(to)) {
      return from == to;
    }
    final mass = const {'g', 'kg'};
    final volume = const {'ml', 'l'};
    if (mass.contains(from) || mass.contains(to)) {
      return mass.contains(from) && mass.contains(to);
    }
    if (volume.contains(from) || volume.contains(to)) {
      return volume.contains(from) && volume.contains(to);
    }
    return from == to;
  }

  /// Number of stock units represented by one entered purchase unit.
  static double quantityRatio({required String purchaseUnit, required String stockUnit}) {
    if (!areCompatible(purchaseUnit, stockUnit)) {
      throw ArgumentError('واحد خرید با واحد انبار سازگار نیست.');
    }
    return (_baseFactor[purchaseUnit] ?? 1) / (_baseFactor[stockUnit] ?? 1);
  }

  static double convertQuantity({
    required num quantity,
    required String purchaseUnit,
    required String stockUnit,
  }) => quantity * quantityRatio(purchaseUnit: purchaseUnit, stockUnit: stockUnit);

  /// Converts price per purchase unit into price per stock unit.
  static double convertUnitCost({
    required num costPerPurchaseUnit,
    required String purchaseUnit,
    required String stockUnit,
  }) => costPerPurchaseUnit / quantityRatio(purchaseUnit: purchaseUnit, stockUnit: stockUnit);

  /// Accepts Latin, Persian and Arabic-Indic digits and decimal separators.
  static double? parseLocalizedNumber(String raw) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var normalized = raw.trim();
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
    }
    normalized = normalized
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll('٫', '.')
        .replaceAll('،', '.')
        .replaceAll(' ', '');
    return double.tryParse(normalized);
  }
}
