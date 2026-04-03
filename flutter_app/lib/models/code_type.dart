import '../l10n/translations.dart';

/// Typ zeskanowanego kodu
enum CodeType {
  barcode,
  productCode;

  String get apiValue => switch (this) {
    CodeType.barcode => 'barcode',
    CodeType.productCode => 'product_code',
  };

  String get label => switch (this) {
    CodeType.barcode => tr('CODE_TYPE_BARCODE'),
    CodeType.productCode => tr('CODE_TYPE_PRODUCT_CODE'),
  };

  static CodeType fromApi(String? value) => switch (value) {
    'product_code' => CodeType.productCode,
    _ => CodeType.barcode,
  };

  /// Rozpoznaj typ kodu na podstawie zawartości.
  /// Kod kreskowy (EAN/UPC): tylko cyfry, 8-13 znaków.
  /// Kod produktu: zawiera litery, kropki, myślniki, spacje.
  static CodeType detect(String code) {
    final trimmed = code.trim();
    if (RegExp(r'^\d{8,13}$').hasMatch(trimmed)) {
      return CodeType.barcode;
    }
    return CodeType.productCode;
  }
}
