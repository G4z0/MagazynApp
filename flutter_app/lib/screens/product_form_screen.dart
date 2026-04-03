import 'package:flutter/material.dart';
import '../models/code_type.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';

/// Ekran formularza ruchu magazynowego (przyjęcie / wydanie)
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
  final _noteController = TextEditingController();
  final _piecesPerPackageController = TextEditingController();

  bool _isSaving = false;
  bool _isChecking = true;
  String? _existingName;
  String _selectedUnit = 'szt';
  String _movementType = 'in'; // 'in' lub 'out'
  String _targetUnit = 'szt'; // docelowa jednostka przy przeliczeniu opak/kpl
  late CodeType _codeType;

  /// Czy wybrana jednostka to opakowanie/komplet (wymaga przeliczenia)
  bool get _isCompoundUnit => _selectedUnit == 'opak' || _selectedUnit == 'kpl';

  /// Jednostki bazowe (do przeliczenia z opakowania)
  static const _baseUnits = [
    (value: 'szt', label: 'Sztuki'),
    (value: 'l', label: 'Litry'),
    (value: 'kg', label: 'Kilogramy'),
    (value: 'm', label: 'Metry'),
  ];

  // Dane ze serwera
  List<Map<String, dynamic>> _stockByUnit = [];
  List<Map<String, dynamic>> _movements = [];

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
    _noteController.dispose();
    _piecesPerPackageController.dispose();
    super.dispose();
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  double _currentStockForUnit(String unit) {
    for (final s in _stockByUnit) {
      if (s['unit'] == unit) {
        return double.tryParse(s['current_stock'].toString()) ?? 0;
      }
    }
    return 0;
  }

  /// Sprawdź czy kod już istnieje w bazie — pobierz stan i historię
  Future<void> _checkExistingBarcode() async {
    final result = await ApiService.checkBarcode(widget.barcode);
    if (mounted) {
      setState(() {
        _isChecking = false;
        if (result != null) {
          final data = result['data'] as Map<String, dynamic>?;
          if (data != null) {
            _existingName = data['product_name'] as String?;
            _nameController.text = _existingName ?? '';
            if (data['code_type'] != null) {
              _codeType = CodeType.fromApi(data['code_type'] as String);
            }
          }
          if (result['stock'] != null) {
            _stockByUnit = List<Map<String, dynamic>>.from(
              (result['stock'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
            // Ustaw jednostkę na pierwszą z istniejących stanów
            if (_stockByUnit.isNotEmpty) {
              _selectedUnit = _stockByUnit.first['unit'] as String? ?? 'szt';
            }
          }
          if (result['movements'] != null) {
            _movements = List<Map<String, dynamic>>.from(
              (result['movements'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          }
        }
      });
    }
  }

  /// Zapisz ruch magazynowy
  Future<void> _saveMovement() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final barcode = widget.barcode;
    final productName = _nameController.text.trim();
    final rawQuantity = double.tryParse(_quantityController.text.trim()) ?? 1;
    var userNote = _noteController.text.trim();

    // Przelicz opakowania/komplety na docelową jednostkę
    double quantity;
    String unit;
    if (_isCompoundUnit && _piecesPerPackageController.text.trim().isNotEmpty) {
      final pcsPerPkg = double.tryParse(_piecesPerPackageController.text.trim()) ?? 1;
      quantity = rawQuantity * pcsPerPkg;
      unit = _targetUnit;
      final unitLabel = _selectedUnit == 'opak' ? 'opak' : 'kpl';
      final conversionInfo = '${_formatQty(rawQuantity)} $unitLabel × ${_formatQty(pcsPerPkg)} $_targetUnit/$unitLabel = ${_formatQty(quantity)} $_targetUnit';
      userNote = userNote.isNotEmpty ? '$conversionInfo; $userNote' : conversionInfo;
    } else {
      quantity = rawQuantity;
      unit = _selectedUnit;
    }
    final note = userNote.isNotEmpty ? userNote : null;

    try {
      final result = await ApiService.saveProduct(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
        movementType: _movementType,
        note: note,
      );

      if (!mounted) return;

      final message = result['message'] ?? 'Zapisano';

      // Loguj do lokalnej historii
      final label = _movementType == 'in' ? 'Przyjęcie' : 'Wydanie';
      await LocalHistoryService().add(
        actionType: _movementType == 'in' ? 'stock_in' : 'stock_out',
        title: '$label: $productName',
        subtitle: '${_formatQty(quantity)} $unit — $barcode',
        barcode: barcode,
        quantity: quantity,
        unit: unit,
        userName: AuthService().displayName,
      );

      _showSuccessDialog(message);
    } on NetworkException {
      await OfflineQueueService().enqueue(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
        movementType: _movementType,
        note: note,
      );

      final label = _movementType == 'in' ? 'Przyjęcie' : 'Wydanie';
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
      _showErrorSnackBar(e.message);
    } catch (e) {
      await OfflineQueueService().enqueue(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
        movementType: _movementType,
        note: note,
      );

      final label2 = _movementType == 'in' ? 'Przyjęcie' : 'Wydanie';
      await LocalHistoryService().add(
        actionType: _movementType == 'in' ? 'stock_in' : 'stock_out',
        title: '$label2 (offline): $productName',
        subtitle: '${_formatQty(quantity)} $unit — $barcode',
        barcode: barcode,
        quantity: quantity,
        unit: unit,
        userName: AuthService().displayName,
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
        backgroundColor: const Color(0xFF2C2F3A),
        icon: const Icon(Icons.cloud_off, color: Colors.orange, size: 48),
        title: const Text('Zapisano w kolejce', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Brak po\u0142\u0105czenia z serwerem. Ruch zostanie wys\u0142any automatycznie gdy WiFi wr\u00f3ci.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
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
        backgroundColor: const Color(0xFF2C2F3A),
        icon: Icon(
          _movementType == 'in' ? Icons.add_circle : Icons.remove_circle,
          color: _accent,
          size: 48,
        ),
        title: const Text('Sukces!', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Ponów',
          textColor: Colors.white,
          onPressed: _saveMovement,
        ),
      ),
    );
  }

  static const Color _accent = Color(0xFF3498DB);
  static const Color _darkBg = Color(0xFF1C1E26);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);

  @override
  Widget build(BuildContext context) {
    final isOut = _movementType == 'out';
    // Dla opak/kpl sprawdzamy stan w docelowej jednostce
    final effectiveUnit = _isCompoundUnit ? _targetUnit : _selectedUnit;
    final stockForUnit = _currentStockForUnit(effectiveUnit);

    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        title: Text(isOut ? 'Wydanie towaru' : 'Przyjęcie towaru'),
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
              // Karta z kodem i stanem magazynowym
              Container(
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _codeType == CodeType.barcode
                          ? Icons.qr_code_2
                          : Icons.tag,
                      size: 48,
                      color: _accent,
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(
                        _codeType == CodeType.barcode
                            ? Icons.qr_code
                            : Icons.badge,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(_codeType.label, style: const TextStyle(color: Colors.white)),
                      backgroundColor: _accent.withAlpha(200),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      widget.barcode,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
                    // Stan magazynowy
                    if (_stockByUnit.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(color: Colors.white.withAlpha(30)),
                      const Text(
                        'Stan magazynowy:',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 6),
                      ..._stockByUnit.map((s) {
                        final stock = double.tryParse(s['current_stock'].toString()) ?? 0;
                        final unit = s['unit'] as String? ?? 'szt';
                        final totalIn = double.tryParse(s['total_in'].toString()) ?? 0;
                        final totalOut = double.tryParse(s['total_out'].toString()) ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                stock > 0 ? Icons.check_circle : Icons.warning,
                                color: stock > 0 ? Colors.green.shade400 : Colors.red.shade400,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_formatQty(stock)} $unit',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: stock > 0 ? Colors.green.shade300 : Colors.red.shade300,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(+${_formatQty(totalIn)} / -${_formatQty(totalOut)})',
                                style: const TextStyle(fontSize: 12, color: Colors.white38),
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else if (!_isChecking) ...[
                      const SizedBox(height: 12),
                      Divider(color: Colors.white.withAlpha(30)),
                      const Text(
                        'Nowy produkt — brak w magazynie',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Przełącznik Przyjęcie / Wydanie
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'in',
                    label: Text('Przyjęcie'),
                    icon: Icon(Icons.add_circle_outline),
                  ),
                  ButtonSegment(
                    value: 'out',
                    label: Text('Wydanie'),
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                ],
                selected: {_movementType},
                onSelectionChanged: (value) {
                  setState(() => _movementType = value.first);
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return isOut ? Colors.orange.shade900.withAlpha(180) : Colors.green.shade900.withAlpha(180);
                    }
                    return _cardBg;
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                  side: WidgetStateProperty.all(BorderSide(color: Colors.white.withAlpha(30))),
                ),
              ),

              const SizedBox(height: 20),

              // Formularz
              if (_isChecking)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: _accent),
                  ),
                )
              else ...[
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nazwa produktu',
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: 'Wpisz nazwę produktu...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.inventory_2, color: _accent),
                    filled: true,
                    fillColor: _inputBg,
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

                // Ilość i jednostka
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Ilość',
                          labelStyle: const TextStyle(color: Colors.white54),
                          hintText: '1',
                          hintStyle: const TextStyle(color: Colors.white24),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          prefixIcon: const Icon(Icons.numbers, color: _accent),
                          filled: true,
                          fillColor: _inputBg,
                          helperText: isOut && stockForUnit > 0
                              ? 'Dostępne: ${_formatQty(stockForUnit)}'
                              : null,
                          helperStyle: TextStyle(color: Colors.green.shade400),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Podaj ilość';
                          }
                          final qty = double.tryParse(value.trim());
                          if (qty == null || qty <= 0) {
                            return 'Ilość > 0';
                          }
                          if (isOut && !_isCompoundUnit && qty > stockForUnit) {
                            return 'Max: ${_formatQty(stockForUnit)}';
                          }
                          if (isOut && _isCompoundUnit) {
                            final pcs = double.tryParse(_piecesPerPackageController.text.trim() ) ?? 0;
                            if (pcs > 0 && qty * pcs > stockForUnit) {
                              return 'Max: ${_formatQty(stockForUnit)} $_targetUnit';
                            }
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
                          labelText: 'Jednostka',
                          labelStyle: const TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: _inputBg,
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

                // Przelicznik w opakowaniu/komplecie
                if (_isCompoundUnit) ...[                  
                  const SizedBox(height: 16),
                  // Wiersz: [ilość w opak] + [docelowa jednostka]
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _piecesPerPackageController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: _selectedUnit == 'opak'
                                ? 'Ile w opakowaniu?'
                                : 'Ile w komplecie?',
                            labelStyle: const TextStyle(color: Colors.white54),
                            hintText: 'np. 10',
                            hintStyle: const TextStyle(color: Colors.white24),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            prefixIcon: const Icon(Icons.calculate, color: _accent),
                            filled: true,
                            fillColor: _inputBg,
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Podaj ilość w ${_selectedUnit == 'opak' ? 'opak.' : 'kpl.'}';
                            }
                            final pcs = double.tryParse(value.trim());
                            if (pcs == null || pcs <= 0) {
                              return '> 0';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _targetUnit,
                          isExpanded: true,
                          dropdownColor: _cardBg,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Jedn.',
                            labelStyle: const TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: _inputBg,
                          ),
                          items: _baseUnits.map((u) => DropdownMenuItem(
                            value: u.value,
                            child: Text(u.label),
                          )).toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _targetUnit = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  // Podsumowanie przeliczenia
                  if (_piecesPerPackageController.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _accent.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: _accent),
                          const SizedBox(width: 8),
                          Text(
                            'Razem: ${_formatQty((double.tryParse(_quantityController.text) ?? 0) * (double.tryParse(_piecesPerPackageController.text) ?? 0))} $_targetUnit',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 16),

                // Notatka (opcjonalna)
                TextFormField(
                  controller: _noteController,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: isOut ? 'Notatka (np. kto pobiera)' : 'Notatka (opcjonalnie)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: isOut ? 'np. Mechanik Kowalski' : 'np. Dostawa z hurtowni',
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.note, color: _accent),
                    filled: true,
                    fillColor: _inputBg,
                  ),
                  maxLength: 255,
                ),

                const SizedBox(height: 20),

                // Przycisk zapisz
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveMovement,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(isOut ? Icons.remove_circle : Icons.add_circle, color: Colors.white),
                  label: Text(
                    _isSaving
                        ? 'Zapisywanie...'
                        : isOut ? 'Wydaj towar' : 'Przyjmij towar',
                    style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),

                // Historia przedmiotów
                if (_movements.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Divider(color: Colors.white.withAlpha(30)),
                  const Text(
                    'Ostatnie ruchy:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  ..._movements.take(10).map((m) {
                    final mType = m['movement_type'] as String? ?? 'in';
                    final qty = double.tryParse(m['quantity'].toString()) ?? 0;
                    final unit = m['unit'] as String? ?? 'szt';
                    final note = m['note'] as String?;
                    final date = m['created_at'] as String? ?? '';
                    final isIn = mType == 'in';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isIn ? Icons.add_circle : Icons.remove_circle,
                        color: isIn ? Colors.green.shade400 : Colors.orange.shade400,
                        size: 20,
                      ),
                      title: Text(
                        '${isIn ? '+' : '-'}${_formatQty(qty)} $unit',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIn ? Colors.green.shade300 : Colors.orange.shade300,
                        ),
                      ),
                      subtitle: note != null && note.isNotEmpty ? Text(note, style: const TextStyle(color: Colors.white38)) : null,
                      trailing: Text(
                        _formatDate(date),
                        style: const TextStyle(fontSize: 11, color: Colors.white24),
                      ),
                    );
                  }),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
