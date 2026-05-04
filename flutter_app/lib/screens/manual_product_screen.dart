import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../models/code_type.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Ekran ręcznego dodawania produktu bez skanowania kodu.
/// Automatycznie generuje wewnętrzny kod SAS-N.
class ManualProductScreen extends StatefulWidget {
  const ManualProductScreen({super.key});

  @override
  State<ManualProductScreen> createState() => _ManualProductScreenState();
}

class _ManualProductScreenState extends State<ManualProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  final _minQuantityController = TextEditingController();
  final _rackController = TextEditingController();
  final _shelfController = TextEditingController();

  bool _isSaving = false;
  bool _isLoadingCode = true;
  String _generatedCode = '';
  Map<String, dynamic>? _selectedExistingProduct;
  String _selectedUnit = 'szt';
  final String _movementType = 'in';

  static const List<({String value, String key, IconData icon})> _units = [
    (value: 'szt', key: 'UNIT_PIECES', icon: Icons.inventory_2),
    (value: 'opak', key: 'UNIT_PACKAGES', icon: Icons.archive),
    (value: 'l', key: 'UNIT_LITRES', icon: Icons.water_drop),
    (value: 'kg', key: 'UNIT_KILOGRAMS', icon: Icons.scale),
    (value: 'm', key: 'UNIT_METRES', icon: Icons.straighten),
    (value: 'kpl', key: 'UNIT_SETS', icon: Icons.widgets),
  ];

  static const Color _accent = AppColors.accent;
  static const Color _darkBg = AppColors.darkBg;
  static const Color _cardBg = AppColors.cardBg;
  static const Color _inputBg = AppColors.inputBg;

  @override
  void initState() {
    super.initState();
    _loadNextCode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    _minQuantityController.dispose();
    _rackController.dispose();
    _shelfController.dispose();
    super.dispose();
  }

  Future<void> _loadNextCode() async {
    final code = await ApiService.getNextSasCode();
    if (mounted) {
      setState(() {
        _generatedCode = code;
        _isLoadingCode = false;
      });
    }
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  bool get _hasSelectedExistingProduct => _selectedExistingProduct != null;

  String get _activeCode {
    final existingCode =
        _selectedExistingProduct?['barcode']?.toString().trim();
    if (existingCode != null && existingCode.isNotEmpty) {
      return existingCode;
    }
    return _generatedCode;
  }

  CodeType get _activeCodeType {
    final raw = _selectedExistingProduct?['code_type']?.toString();
    if (raw != null && raw.isNotEmpty) {
      return CodeType.fromApi(raw);
    }
    return CodeType.detect(_activeCode);
  }

  Future<void> _showExistingProductPicker() async {
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExistingProductPickerSheet(),
    );
    if (product == null || !mounted) return;
    _applyExistingProduct(product);
  }

  void _applyExistingProduct(Map<String, dynamic> product) {
    final name = product['product_name']?.toString() ?? '';
    final unit = product['unit']?.toString() ?? 'szt';
    final minQuantity = product['min_quantity'];
    final rack = product['location_rack']?.toString().trim();
    final shelf = product['location_shelf'];
    final normalizedUnit =
        _units.any((availableUnit) => availableUnit.value == unit)
            ? unit
            : 'szt';

    setState(() {
      _selectedExistingProduct = product;
      _nameController.text = name;
      _selectedUnit = normalizedUnit;
      _minQuantityController.text =
          minQuantity == null ? '' : _formatQty(minQuantity);
      _rackController.text = rack == null || rack.isEmpty ? '' : rack;
      _shelfController.text = shelf == null ? '' : shelf.toString();
    });
  }

  void _clearExistingProduct() {
    setState(() {
      _selectedExistingProduct = null;
      _nameController.clear();
      _selectedUnit = 'szt';
      _minQuantityController.clear();
      _rackController.clear();
      _shelfController.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final barcode = _activeCode;
    final productName = _nameController.text.trim();
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 1;
    final unit = _selectedUnit;
    final note = _noteController.text.trim().isNotEmpty
        ? _noteController.text.trim()
        : null;

    // Minimalny stan (opcjonalny)
    final minQuantityText =
        _minQuantityController.text.trim().replaceAll(',', '.');
    final double? minQuantity =
        minQuantityText.isEmpty ? null : double.tryParse(minQuantityText);

    // Lokalizacja (opcjonalna). Walidacja w validatorach formularza.
    final rackText = _rackController.text.trim().toUpperCase();
    final shelfText = _shelfController.text.trim();
    final String? locationRack = rackText.isEmpty ? null : rackText;
    final int? locationShelf =
        shelfText.isEmpty ? null : int.tryParse(shelfText);

    try {
      final result = await ApiService.saveProduct(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _activeCodeType,
        movementType: _movementType,
        note: note,
        locationRack: locationRack,
        locationShelf: locationShelf,
        minQuantity: minQuantity,
      );

      if (!mounted) return;

      final message = result['message'] ?? 'Zapisano';

      final label =
          _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
      await LocalHistoryService().add(
        actionType: _movementType == 'in' ? 'stock_in' : 'stock_out',
        title: '$label: $productName',
        subtitle: '${_formatQty(quantity)} $unit — $barcode',
        barcode: barcode,
        quantity: quantity,
        unit: unit,
        userName: AuthService().displayName,
      );

      _showSuccessDialog(message, barcode);
    } on NetworkException {
      await OfflineQueueService().enqueue(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _activeCodeType,
        movementType: _movementType,
        note: note,
        locationRack: locationRack,
        locationShelf: locationShelf,
        minQuantity: minQuantity,
      );

      final label =
          _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
      await LocalHistoryService().add(
        actionType: _movementType == 'in' ? 'stock_in' : 'stock_out',
        title: '$label (offline): $productName',
        subtitle: '${_formatQty(quantity)} $unit — $barcode',
        barcode: barcode,
        quantity: quantity,
        unit: unit,
        userName: AuthService().displayName,
      );

      if (!mounted) return;
      _showQueuedDialog();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      await OfflineQueueService().enqueue(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _activeCodeType,
        movementType: _movementType,
        note: note,
        locationRack: locationRack,
        locationShelf: locationShelf,
        minQuantity: minQuantity,
      );

      final label =
          _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
      await LocalHistoryService().add(
        actionType: _movementType == 'in' ? 'stock_in' : 'stock_out',
        title: '$label (offline): $productName',
        subtitle: '${_formatQty(quantity)} $unit — $barcode',
        barcode: barcode,
        quantity: quantity,
        unit: unit,
        userName: AuthService().displayName,
      );

      if (!mounted) return;
      _showQueuedDialog();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSuccessDialog(String message, String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        icon: const Icon(Icons.check_circle, color: _accent, size: 48),
        title: Text(tr('DIALOG_SUCCESS_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _accent.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tag, size: 18, color: _accent),
                  const SizedBox(width: 8),
                  Text(
                    '${tr('MANUAL_GENERATED_CODE')}: $code',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _accent,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(tr('BUTTON_CONFIRM')),
          ),
        ],
      ),
    );
  }

  void _showQueuedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        icon: const Icon(Icons.cloud_off, color: Colors.orange, size: 48),
        title: Text(tr('DIALOG_QUEUED_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Text(tr('DIALOG_QUEUED_CONTENT'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(tr('BUTTON_CONFIRM')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        title: Text(tr('MANUAL_TITLE')),
        centerTitle: true,
        backgroundColor: _darkBg,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Karta z kodem produktu: wygenerowanym lub wybranym z bazy.
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _hasSelectedExistingProduct
                          ? Icons.inventory_2
                          : Icons.tag,
                      size: 48,
                      color: _accent,
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(
                          _hasSelectedExistingProduct
                              ? Icons.check_circle
                              : Icons.auto_awesome,
                          size: 16,
                          color: Colors.white),
                      label: Text(
                          _hasSelectedExistingProduct
                              ? tr('MANUAL_EXISTING_PRODUCT')
                              : tr('MANUAL_AUTO_CODE'),
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: _accent.withAlpha(200),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingCode && !_hasSelectedExistingProduct)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent),
                      )
                    else
                      SelectableText(
                        _activeCode,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      _hasSelectedExistingProduct
                          ? tr('MANUAL_EXISTING_PRODUCT_INFO')
                          : tr('MANUAL_CODE_INFO'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white38),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _showExistingProductPicker,
                          icon: const Icon(Icons.search),
                          label: Text(tr('MANUAL_PICK_EXISTING')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: _accent.withAlpha(160)),
                          ),
                        ),
                        if (_hasSelectedExistingProduct)
                          IconButton(
                            onPressed: _clearExistingProduct,
                            icon: const Icon(Icons.close),
                            color: Colors.white70,
                            tooltip: tr('MANUAL_CLEAR_EXISTING'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Nazwa produktu
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('LABEL_PRODUCT_NAME'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: tr('HINT_PRODUCT_NAME'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.inventory_2, color: _accent),
                  filled: true,
                  fillColor: _inputBg,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return tr('VALIDATION_PRODUCT_NAME_REQUIRED');
                  }
                  if (value.trim().length < 2) {
                    return tr('VALIDATION_PRODUCT_NAME_MIN_LENGTH');
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Ilość i jednostka
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: tr('LABEL_QUANTITY'),
                        labelStyle: const TextStyle(color: Colors.white54),
                        hintText: '1',
                        hintStyle: const TextStyle(color: Colors.white24),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.numbers, color: _accent),
                        filled: true,
                        fillColor: _inputBg,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return tr('VALIDATION_QUANTITY_REQUIRED');
                        }
                        final qty = double.tryParse(value.trim());
                        if (qty == null || qty <= 0) {
                          return tr('VALIDATION_QUANTITY_POSITIVE');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_selectedUnit),
                      initialValue: _selectedUnit,
                      isExpanded: true,
                      dropdownColor: _cardBg,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: tr('LABEL_UNIT'),
                        labelStyle: const TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: _inputBg,
                      ),
                      items: _units
                          .map((u) => DropdownMenuItem(
                                value: u.value,
                                child: Text(tr(u.key)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedUnit = value);
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Minimalny stan (opcjonalnie)
              TextFormField(
                controller: _minQuantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: tr('LABEL_MIN_STOCK'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: tr('HINT_MIN_STOCK_OPTIONAL'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.warning_amber, color: _accent),
                  filled: true,
                  fillColor: _inputBg,
                ),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) return null;
                  final n = double.tryParse(v.replaceAll(',', '.'));
                  if (n == null || n < 0) {
                    return tr('MIN_STOCK_VALIDATION');
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Notatka
              TextFormField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('LABEL_NOTE_IN'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: tr('HINT_NOTE_IN'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.note, color: _accent),
                  filled: true,
                  fillColor: _inputBg,
                ),
                maxLength: 255,
              ),

              const SizedBox(height: 8),

              // Lokalizacja w magazynie (opcjonalna): regał + półka
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _rackController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                          color: Colors.white, letterSpacing: 2),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(2),
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          return newValue.copyWith(
                              text: newValue.text.toUpperCase());
                        }),
                      ],
                      decoration: InputDecoration(
                        labelText: tr('LOCATION_RACK'),
                        labelStyle: const TextStyle(color: Colors.white54),
                        hintText: tr('LOCATION_HINT_RACK'),
                        hintStyle: const TextStyle(color: Colors.white24),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.shelves, color: _accent),
                        filled: true,
                        fillColor: _inputBg,
                      ),
                      validator: (value) {
                        final rack = (value ?? '').trim();
                        final shelf = _shelfController.text.trim();
                        if (rack.isEmpty && shelf.isEmpty) return null;
                        if (rack.isEmpty) {
                          return tr('LOCATION_VALIDATION_BOTH_REQUIRED');
                        }
                        if (!RegExp(r'^[A-Z]{1,2}$').hasMatch(rack)) {
                          return tr('LOCATION_VALIDATION_RACK');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _shelfController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(2),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: tr('LOCATION_SHELF'),
                        labelStyle: const TextStyle(color: Colors.white54),
                        hintText: tr('LOCATION_HINT_SHELF'),
                        hintStyle: const TextStyle(color: Colors.white24),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.layers, color: _accent),
                        filled: true,
                        fillColor: _inputBg,
                      ),
                      validator: (value) {
                        final shelf = (value ?? '').trim();
                        final rack = _rackController.text.trim();
                        if (rack.isEmpty && shelf.isEmpty) return null;
                        if (shelf.isEmpty) {
                          return tr('LOCATION_VALIDATION_BOTH_REQUIRED');
                        }
                        final n = int.tryParse(shelf);
                        if (n == null || n < 0 || n > 99) {
                          return tr('LOCATION_VALIDATION_SHELF');
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Przycisk zapisz
              AppPrimaryButton(
                onPressed: (_isLoadingCode && !_hasSelectedExistingProduct)
                    ? null
                    : _save,
                isLoading: _isSaving,
                icon: Icons.add_circle,
                label: _isSaving
                    ? tr('BUTTON_SAVING')
                    : tr('BUTTON_RECEIVE_GOODS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingProductPickerSheet extends StatefulWidget {
  const _ExistingProductPickerSheet();

  @override
  State<_ExistingProductPickerSheet> createState() =>
      _ExistingProductPickerSheetState();
}

class _ExistingProductPickerSheetState
    extends State<_ExistingProductPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;

  static const Color _accent = AppColors.accent;
  static const Color _cardBg = AppColors.cardBg;
  static const Color _inputBg = AppColors.inputBg;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ApiService.getStockList();
      if (!mounted) return;
      setState(() {
        _products = products;
        _filtered = products;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = _products;
        return;
      }

      _filtered = _products.where((product) {
        final name = (product['product_name']?.toString() ?? '').toLowerCase();
        final barcode = (product['barcode']?.toString() ?? '').toLowerCase();
        return name.contains(q) || barcode.contains(q);
      }).toList();
    });
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  String? _formatLocation(Map<String, dynamic> product) {
    final rack = product['location_rack']?.toString().trim();
    final shelf = product['location_shelf'];
    if (rack == null || rack.isEmpty || shelf == null) {
      return null;
    }
    return '$rack$shelf';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('MANUAL_PICK_EXISTING_TITLE'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('STOCK_SEARCH_HINT'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixIcon: const Icon(Icons.search, color: _accent),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38),
                          onPressed: () {
                            _searchController.clear();
                            _filter('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: _inputBg,
                ),
                onChanged: _filter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} ${tr('PRODUCT_PLURAL_MANY')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            tr('LABEL_NO_RESULTS'),
                            style: const TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final product = _filtered[i];
                            final barcode =
                                product['barcode']?.toString() ?? '';
                            final name = product['product_name']?.toString() ??
                                tr('PRODUCT_NO_NAME');
                            final unit = product['unit']?.toString() ?? 'szt';
                            final stock = product['current_stock'];
                            final location = _formatLocation(product);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _accent.withAlpha(40),
                                child: const Icon(
                                  Icons.inventory_2,
                                  color: _accent,
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (location != null) ...[
                                    const SizedBox(width: 6),
                                    LocationChip(label: location),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '$barcode  •  ${_formatQty(stock)} $unit',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Icon(
                                Icons.add_circle_outline,
                                color: Colors.green.shade400,
                              ),
                              onTap: () => Navigator.pop(ctx, product),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
