import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../models/code_type.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';

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

  bool _isSaving = false;
  bool _isLoadingCode = true;
  String _generatedCode = '';
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

  static const Color _accent = Color(0xFF3498DB);
  static const Color _darkBg = Color(0xFF1C1E26);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final barcode = _generatedCode;
    final productName = _nameController.text.trim();
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 1;
    final unit = _selectedUnit;
    final note = _noteController.text.trim().isNotEmpty
        ? _noteController.text.trim()
        : null;

    try {
      final result = await ApiService.saveProduct(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: CodeType.productCode,
        movementType: _movementType,
        note: note,
      );

      if (!mounted) return;

      final message = result['message'] ?? 'Zapisano';

      final label = _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
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
        codeType: CodeType.productCode,
        movementType: _movementType,
        note: note,
      );

      final label = _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
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
        codeType: CodeType.productCode,
        movementType: _movementType,
        note: note,
      );

      final label = _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
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
              // Karta z wygenerowanym kodem
              Container(
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.tag, size: 48, color: _accent),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: const Icon(Icons.auto_awesome,
                          size: 16, color: Colors.white),
                      label: Text(tr('MANUAL_AUTO_CODE'),
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: _accent.withAlpha(200),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingCode)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: _accent),
                      )
                    else
                      SelectableText(
                        _generatedCode,
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
                      tr('MANUAL_CODE_INFO'),
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                      textAlign: TextAlign.center,
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
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
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
                      value: _selectedUnit,
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
                        if (value != null) setState(() => _selectedUnit = value);
                      },
                    ),
                  ),
                ],
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

              const SizedBox(height: 20),

              // Przycisk zapisz
              FilledButton.icon(
                onPressed: (_isSaving || _isLoadingCode) ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        Icons.add_circle,
                        color: Colors.white),
                label: Text(
                  _isSaving
                      ? tr('BUTTON_SAVING')
                      : tr('BUTTON_RECEIVE_GOODS'),
                  style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
