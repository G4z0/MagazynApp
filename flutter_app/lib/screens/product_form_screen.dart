import 'package:flutter/material.dart';
import '../models/code_type.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';

/// Ekran formularza do wpisania nazwy produktu
/// po zeskanowaniu kodu kreskowego.
class ProductFormScreen extends StatefulWidget {
  final String barcode;

  const ProductFormScreen({super.key, required this.barcode});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  bool _isSaving = false;
  bool _isChecking = true;
  String? _existingName;
  String _selectedUnit = 'szt';
  late CodeType _codeType;

  static const List<({String value, String label, IconData icon})> _units = [
    (value: 'szt', label: 'Sztuki', icon: Icons.inventory_2),
    (value: 'opak', label: 'Opakowania', icon: Icons.archive),
    (value: 'l', label: 'Litry', icon: Icons.water_drop),
    (value: 'kg', label: 'Kilogramy', icon: Icons.scale),
    (value: 'm', label: 'Metry', icon: Icons.straighten),
    (value: 'kpl', label: 'Komplety', icon: Icons.widgets),
  ];

  @override
  void initState() {
    super.initState();
    _codeType = CodeType.detect(widget.barcode);
    _checkExistingBarcode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  /// Sprawdź czy kod już istnieje w bazie i wstępnie wypełnij nazwę
  Future<void> _checkExistingBarcode() async {
    final existing = await ApiService.checkBarcode(widget.barcode);
    if (mounted) {
      setState(() {
        _isChecking = false;
        if (existing != null) {
          _existingName = existing['product_name'] as String?;
          _nameController.text = _existingName ?? '';
          if (existing['quantity'] != null) {
            final q = double.tryParse(existing['quantity'].toString()) ?? 1;
            _quantityController.text = q == q.roundToDouble()
                ? q.toInt().toString()
                : q.toString();
          }
          if (existing['unit'] != null) {
            _selectedUnit = existing['unit'] as String;
          }
          if (existing['code_type'] != null) {
            _codeType = CodeType.fromApi(existing['code_type'] as String);
          }
        }
      });
    }
  }

  /// Zapisz produkt do bazy danych
  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final barcode = widget.barcode;
    final productName = _nameController.text.trim();
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 1;
    final unit = _selectedUnit;

    try {
      final result = await ApiService.saveProduct(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
      );

      if (!mounted) return;

      final message = result['message'] ?? 'Zapisano';
      _showSuccessDialog(message);
    } on NetworkException {
      // Brak sieci — zapisz do kolejki offline
      await OfflineQueueService().enqueue(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
      );

      if (!mounted) return;
      _showQueuedDialog();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.message);
    } catch (e) {
      // Timeout itp. — też kolejkuj
      await OfflineQueueService().enqueue(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
      );

      if (!mounted) return;
      _showQueuedDialog();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showQueuedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_off, color: Colors.orange, size: 48),
        title: const Text('Zapisano w kolejce'),
        content: const Text(
          'Brak połączenia z serwerem. Produkt zostanie wysłany automatycznie gdy WiFi wróci.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Skanuj następny'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Sukces!'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);  // Zamknij dialog
              Navigator.pop(context); // Wróć do skanera
            },
            child: const Text('Skanuj następny'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Ponów',
          textColor: Colors.white,
          onPressed: _saveProduct,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dodaj produkt'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Karta z zeskanowanym kodem
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        _codeType == CodeType.barcode
                            ? Icons.qr_code_2
                            : Icons.tag,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        avatar: Icon(
                          _codeType == CodeType.barcode
                              ? Icons.qr_code
                              : Icons.badge,
                          size: 16,
                        ),
                        label: Text(_codeType.label),
                        backgroundColor: _codeType == CodeType.barcode
                            ? Colors.blue.shade50
                            : Colors.purple.shade50,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        widget.barcode,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      if (_existingName != null) ...[
                        const SizedBox(height: 8),
                        Chip(
                          avatar: const Icon(Icons.info, size: 16),
                          label: const Text('Kod już istnieje w bazie'),
                          backgroundColor:
                              Colors.orange.shade100,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Pole na nazwę produktu
              if (_isChecking)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa produktu',
                    hintText: 'Wpisz nazwę produktu...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.inventory_2),
                    filled: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Wpisz nazwę produktu';
                    }
                    if (value.trim().length < 2) {
                      return 'Nazwa musi mieć co najmniej 2 znaki';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Ilość i jednostka w jednym wierszu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pole ilości
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Ilość',
                          hintText: '1',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.numbers),
                          filled: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Podaj ilość';
                          }
                          final qty = double.tryParse(value.trim());
                          if (qty == null || qty <= 0) {
                            return 'Ilość > 0';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Wybór jednostki
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Jednostka',
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                        items: _units.map((u) => DropdownMenuItem(
                          value: u.value,
                          child: Text(u.label),
                        )).toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _selectedUnit = value);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Przycisk zapisz
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveProduct,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isSaving
                        ? 'Zapisywanie...'
                        : (_existingName != null ? 'Aktualizuj' : 'Zapisz'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
