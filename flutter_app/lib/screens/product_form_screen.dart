import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../models/code_type.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';

/// Ekran formularza ruchu magazynowego (przyjęcie / wydanie)
/// po zeskanowaniu kodu kreskowego.
class ProductFormScreen extends StatefulWidget {
  final String barcode;
  final String initialMovementType;

  const ProductFormScreen(
      {super.key, required this.barcode, this.initialMovementType = 'in'});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  final _piecesPerPackageController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  final _rackController = TextEditingController();
  final _shelfController = TextEditingController();

  bool _isSaving = false;
  bool _isChecking = true;
  String? _existingName;
  String _selectedUnit = 'szt';
  String _movementType = 'in'; // 'in' lub 'out'
  String _targetUnit = 'szt'; // docelowa jednostka przy przeliczeniu opak/kpl
  String _issueReason = 'departure'; // 'departure' lub 'replacement'
  String _issueTarget = 'vehicle'; // 'vehicle' lub 'driver'
  List<Map<String, dynamic>> _drivers = [];
  int? _selectedDriverId;
  String? _selectedDriverName;
  bool _isLoadingDrivers = false;
  late CodeType _codeType;

  /// Czy wybrana jednostka to opakowanie/komplet (wymaga przeliczenia)
  bool get _isCompoundUnit => _selectedUnit == 'opak' || _selectedUnit == 'kpl';

  /// Jednostki bazowe (do przeliczenia z opakowania)
  static const _baseUnits = [
    (value: 'szt', key: 'UNIT_PIECES'),
    (value: 'l', key: 'UNIT_LITRES'),
    (value: 'kg', key: 'UNIT_KILOGRAMS'),
    (value: 'm', key: 'UNIT_METRES'),
  ];

  // Dane ze serwera
  List<Map<String, dynamic>> _stockByUnit = [];
  List<Map<String, dynamic>> _movements = [];

  static const List<({String value, String key, IconData icon})> _units = [
    (value: 'szt', key: 'UNIT_PIECES', icon: Icons.inventory_2),
    (value: 'opak', key: 'UNIT_PACKAGES', icon: Icons.archive),
    (value: 'l', key: 'UNIT_LITRES', icon: Icons.water_drop),
    (value: 'kg', key: 'UNIT_KILOGRAMS', icon: Icons.scale),
    (value: 'm', key: 'UNIT_METRES', icon: Icons.straighten),
    (value: 'kpl', key: 'UNIT_SETS', icon: Icons.widgets),
  ];

  @override
  void initState() {
    super.initState();
    _movementType = widget.initialMovementType;
    _codeType = CodeType.detect(widget.barcode);
    _checkExistingBarcode();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    setState(() => _isLoadingDrivers = true);
    try {
      final drivers = await ApiService.getDrivers();
      if (mounted) {
        setState(() {
          _drivers = drivers;
          _isLoadingDrivers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDrivers = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    _piecesPerPackageController.dispose();
    _vehiclePlateController.dispose();
    _rackController.dispose();
    _shelfController.dispose();
    super.dispose();
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  /// Sformatowana lokalizacja w magazynie, np. "A0" / "AB12".
  /// Zwraca `null`, gdy nie ma kompletu regał+półka.
  String? _formatLocation() {
    final rack = _rackController.text.trim().toUpperCase();
    final shelfText = _shelfController.text.trim();
    if (rack.isEmpty || shelfText.isEmpty) return null;
    final shelf = int.tryParse(shelfText);
    if (shelf == null) return null;
    return '$rack$shelf';
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
            final rack = data['location_rack'] as String?;
            final shelf = data['location_shelf'];
            if (rack != null && rack.isNotEmpty) {
              _rackController.text = rack;
            }
            if (shelf != null) {
              _shelfController.text = shelf.toString();
            }
          }
          if (result['stock'] != null) {
            _stockByUnit = List<Map<String, dynamic>>.from(
              (result['stock'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)),
            );
            // Ustaw jednostkę na pierwszą z istniejących stanów
            if (_stockByUnit.isNotEmpty) {
              _selectedUnit = _stockByUnit.first['unit'] as String? ?? 'szt';
            }
          }
          if (result['movements'] != null) {
            _movements = List<Map<String, dynamic>>.from(
              (result['movements'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)),
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
      final pcsPerPkg =
          double.tryParse(_piecesPerPackageController.text.trim()) ?? 1;
      quantity = rawQuantity * pcsPerPkg;
      unit = _targetUnit;
      final unitLabel = _selectedUnit == 'opak' ? 'opak' : 'kpl';
      final conversionInfo =
          '${_formatQty(rawQuantity)} $unitLabel × ${_formatQty(pcsPerPkg)} $_targetUnit/$unitLabel = ${_formatQty(quantity)} $_targetUnit';
      userNote =
          userNote.isNotEmpty ? '$conversionInfo; $userNote' : conversionInfo;
    } else {
      quantity = rawQuantity;
      unit = _selectedUnit;
    }
    final note = userNote.isNotEmpty ? userNote : null;

    // Lokalizacja w magazynie — opcjonalna; zapisujemy tylko przy przyjęciu.
    final rackText = _rackController.text.trim().toUpperCase();
    final shelfText = _shelfController.text.trim();
    final String? locationRack =
        (_movementType == 'in' && rackText.isNotEmpty) ? rackText : null;
    final int? locationShelf = (_movementType == 'in' && shelfText.isNotEmpty)
        ? int.tryParse(shelfText)
        : null;

    try {
      final result = await ApiService.saveProduct(
        barcode: barcode,
        productName: productName,
        quantity: quantity,
        unit: unit,
        codeType: _codeType,
        movementType: _movementType,
        note: note,
        locationRack: locationRack,
        locationShelf: locationShelf,
        issueReason: _movementType == 'out' ? _issueReason : null,
        vehiclePlate: _movementType == 'out' && _issueTarget == 'vehicle'
            ? _vehiclePlateController.text.trim()
            : null,
        issueTarget: _movementType == 'out' ? _issueTarget : null,
        driverId: _movementType == 'out' && _issueTarget == 'driver'
            ? _selectedDriverId
            : null,
        driverName: _movementType == 'out' && _issueTarget == 'driver'
            ? _selectedDriverName
            : null,
      );

      if (!mounted) return;

      final message = result['message'] ?? 'Zapisano';

      // Loguj do lokalnej historii
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
        locationRack: locationRack,
        locationShelf: locationShelf,
        issueReason: _movementType == 'out' ? _issueReason : null,
        vehiclePlate: _movementType == 'out' && _issueTarget == 'vehicle'
            ? _vehiclePlateController.text.trim()
            : null,
        issueTarget: _movementType == 'out' ? _issueTarget : null,
        driverId: _movementType == 'out' && _issueTarget == 'driver'
            ? _selectedDriverId
            : null,
        driverName: _movementType == 'out' && _issueTarget == 'driver'
            ? _selectedDriverName
            : null,
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
        locationRack: locationRack,
        locationShelf: locationShelf,
        issueReason: _movementType == 'out' ? _issueReason : null,
        vehiclePlate: _movementType == 'out' && _issueTarget == 'vehicle'
            ? _vehiclePlateController.text.trim()
            : null,
        issueTarget: _movementType == 'out' ? _issueTarget : null,
        driverId: _movementType == 'out' && _issueTarget == 'driver'
            ? _selectedDriverId
            : null,
        driverName: _movementType == 'out' && _issueTarget == 'driver'
            ? _selectedDriverName
            : null,
      );

      final label2 =
          _movementType == 'in' ? tr('LOG_STOCK_IN') : tr('LOG_STOCK_OUT');
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
        title: Text(tr('DIALOG_QUEUED_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          tr('DIALOG_QUEUED_CONTENT'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(tr('BUTTON_SCAN_NEXT')),
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
        title: Text(tr('DIALOG_SUCCESS_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(tr('BUTTON_SCAN_NEXT')),
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
          label: tr('BUTTON_RETRY'),
          textColor: Colors.white,
          onPressed: _saveMovement,
        ),
      ),
    );
  }

  void _showDriverSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _DriverSearchDialog(
        drivers: _drivers,
        onSelected: (id, name) {
          setState(() {
            _selectedDriverId = id;
            _selectedDriverName = name;
          });
        },
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
        title: Text(isOut ? tr('FORM_TITLE_OUT') : tr('FORM_TITLE_IN')),
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
              Stack(
                children: [
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
                          label: Text(_codeType.label,
                              style: const TextStyle(color: Colors.white)),
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
                          Text(
                            tr('FORM_STOCK_LEVEL'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54),
                          ),
                          const SizedBox(height: 6),
                          ..._stockByUnit.map((s) {
                            final stock = double.tryParse(
                                    s['current_stock'].toString()) ??
                                0;
                            final unit = s['unit'] as String? ?? 'szt';
                            final totalIn =
                                double.tryParse(s['total_in'].toString()) ?? 0;
                            final totalOut =
                                double.tryParse(s['total_out'].toString()) ?? 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    stock > 0
                                        ? Icons.check_circle
                                        : Icons.warning,
                                    color: stock > 0
                                        ? Colors.green.shade400
                                        : Colors.red.shade400,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_formatQty(stock)} $unit',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: stock > 0
                                          ? Colors.green.shade300
                                          : Colors.red.shade300,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(+${_formatQty(totalIn)} / -${_formatQty(totalOut)})',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white38),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ] else if (!_isChecking) ...[
                          const SizedBox(height: 12),
                          Divider(color: Colors.white.withAlpha(30)),
                          Text(
                            tr('FORM_NEW_PRODUCT'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white38),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Lokalizacja w magazynie (regał + półka) — chip w prawym górnym rogu.
                  if (_formatLocation() != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _accent.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _accent.withAlpha(120)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pin_drop,
                                size: 14, color: _accent),
                            const SizedBox(width: 4),
                            Text(
                              _formatLocation()!,
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // Przełącznik Przyjęcie / Wydanie
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'in',
                    label: Text(tr('MOVEMENT_IN')),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  ButtonSegment(
                    value: 'out',
                    label: Text(tr('MOVEMENT_OUT')),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
                selected: {_movementType},
                onSelectionChanged: (value) {
                  setState(() => _movementType = value.first);
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return isOut
                          ? Colors.orange.shade900.withAlpha(180)
                          : Colors.green.shade900.withAlpha(180);
                    }
                    return _cardBg;
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                  side: WidgetStateProperty.all(
                      BorderSide(color: Colors.white.withAlpha(30))),
                ),
              ),

              const SizedBox(height: 20),

              // --- Pola wydania (widoczne tylko przy 'out') ---
              if (isOut) ...[
                // Powód wydania
                Text(
                  tr('LABEL_ISSUE_REASON'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'departure',
                      label: Text(tr('ISSUE_DEPARTURE')),
                      icon: const Icon(Icons.departure_board),
                    ),
                    ButtonSegment(
                      value: 'replacement',
                      label: Text(tr('ISSUE_REPLACEMENT')),
                      icon: const Icon(Icons.swap_horiz),
                    ),
                  ],
                  selected: {_issueReason},
                  onSelectionChanged: (value) {
                    setState(() => _issueReason = value.first);
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.orange.shade800.withAlpha(180);
                      }
                      return _cardBg;
                    }),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    side: WidgetStateProperty.all(
                        BorderSide(color: Colors.white.withAlpha(30))),
                  ),
                ),
                const SizedBox(height: 16),

                // Cel wydania: samochód / kierowca
                Text(
                  tr('LABEL_ISSUE_TARGET'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'vehicle',
                      label: Text(tr('ISSUE_TO_VEHICLE')),
                      icon: const Icon(Icons.local_shipping),
                    ),
                    ButtonSegment(
                      value: 'driver',
                      label: Text(tr('ISSUE_TO_DRIVER')),
                      icon: const Icon(Icons.person),
                    ),
                    ButtonSegment(
                      value: 'workshop',
                      label: Text(tr('ISSUE_TO_WORKSHOP')),
                      icon: const Icon(Icons.build),
                    ),
                  ],
                  selected: {_issueTarget},
                  onSelectionChanged: (value) {
                    setState(() {
                      _issueTarget = value.first;
                      if (value.first == 'vehicle') {
                        _selectedDriverId = null;
                        _selectedDriverName = null;
                      } else if (value.first == 'driver') {
                        _vehiclePlateController.clear();
                      } else {
                        _vehiclePlateController.clear();
                        _selectedDriverId = null;
                        _selectedDriverName = null;
                      }
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.blue.shade800.withAlpha(180);
                      }
                      return _cardBg;
                    }),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    side: WidgetStateProperty.all(
                        BorderSide(color: Colors.white.withAlpha(30))),
                  ),
                ),
                const SizedBox(height: 16),

                // Samochód (widoczny gdy target = vehicle)
                if (_issueTarget == 'vehicle')
                  TextFormField(
                    controller: _vehiclePlateController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: tr('LABEL_VEHICLE_PLATE'),
                      labelStyle: const TextStyle(color: Colors.white54),
                      hintText: tr('HINT_VEHICLE_PLATE'),
                      hintStyle: const TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      prefixIcon:
                          const Icon(Icons.local_shipping, color: _accent),
                      filled: true,
                      fillColor: _inputBg,
                    ),
                    maxLength: 20,
                    validator: (value) {
                      if (_issueTarget == 'vehicle' &&
                          (value == null || value.trim().isEmpty)) {
                        return tr('VALIDATION_VEHICLE_REQUIRED');
                      }
                      return null;
                    },
                  ),

                // Kierowca (widoczny gdy target = driver)
                if (_issueTarget == 'driver')
                  _isLoadingDrivers
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: CircularProgressIndicator(color: _accent)),
                        )
                      : FormField<int>(
                          initialValue: _selectedDriverId,
                          validator: (value) {
                            if (_issueTarget == 'driver' &&
                                _selectedDriverId == null) {
                              return tr('VALIDATION_DRIVER_REQUIRED');
                            }
                            return null;
                          },
                          builder: (FormFieldState<int> field) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _showDriverSearchDialog(),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: tr('LABEL_SELECT_DRIVER'),
                                      labelStyle: const TextStyle(
                                          color: Colors.white54),
                                      hintText: tr('HINT_SELECT_DRIVER'),
                                      hintStyle: const TextStyle(
                                          color: Colors.white24),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide.none),
                                      prefixIcon: const Icon(Icons.person,
                                          color: _accent),
                                      suffixIcon: const Icon(Icons.search,
                                          color: Colors.white38),
                                      filled: true,
                                      fillColor: _inputBg,
                                      errorText: field.errorText,
                                    ),
                                    child: Text(
                                      _selectedDriverName ??
                                          tr('HINT_SELECT_DRIVER'),
                                      style: TextStyle(
                                        color: _selectedDriverName != null
                                            ? Colors.white
                                            : Colors.white24,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                const SizedBox(height: 16),
                Divider(color: Colors.white.withAlpha(30)),
                const SizedBox(height: 12),
              ],

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
                          helperText: isOut && stockForUnit > 0
                              ? '${tr('LABEL_AVAILABLE')} ${_formatQty(stockForUnit)}'
                              : null,
                          helperStyle: TextStyle(color: Colors.green.shade400),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return tr('VALIDATION_QUANTITY_REQUIRED');
                          }
                          final qty = double.tryParse(value.trim());
                          if (qty == null || qty <= 0) {
                            return tr('VALIDATION_QUANTITY_POSITIVE');
                          }
                          if (isOut && !_isCompoundUnit && qty > stockForUnit) {
                            return '${tr('VALIDATION_MAX')} ${_formatQty(stockForUnit)}';
                          }
                          if (isOut && _isCompoundUnit) {
                            final pcs = double.tryParse(
                                    _piecesPerPackageController.text.trim()) ??
                                0;
                            if (pcs > 0 && qty * pcs > stockForUnit) {
                              return '${tr('VALIDATION_MAX')} ${_formatQty(stockForUnit)} $_targetUnit';
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
                          if (value != null)
                            setState(() => _selectedUnit = value);
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: _selectedUnit == 'opak'
                                ? tr('LABEL_PER_PACKAGE')
                                : tr('LABEL_PER_SET'),
                            labelStyle: const TextStyle(color: Colors.white54),
                            hintText: 'np. 10',
                            hintStyle: const TextStyle(color: Colors.white24),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            prefixIcon:
                                const Icon(Icons.calculate, color: _accent),
                            filled: true,
                            fillColor: _inputBg,
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return tr(_selectedUnit == 'opak'
                                  ? 'VALIDATION_PER_PACKAGE_REQUIRED'
                                  : 'VALIDATION_PER_SET_REQUIRED');
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
                            labelText: tr('LABEL_UNIT_SHORT'),
                            labelStyle: const TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            filled: true,
                            fillColor: _inputBg,
                          ),
                          items: _baseUnits
                              .map((u) => DropdownMenuItem(
                                    value: u.value,
                                    child: Text(tr(u.key)),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null)
                              setState(() => _targetUnit = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  // Podsumowanie przeliczenia
                  if (_piecesPerPackageController.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _accent.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: _accent),
                          const SizedBox(width: 8),
                          Text(
                            '${tr('LABEL_TOTAL')} ${_formatQty((double.tryParse(_quantityController.text) ?? 0) * (double.tryParse(_piecesPerPackageController.text) ?? 0))} $_targetUnit',
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
                    labelText:
                        isOut ? tr('LABEL_NOTE_OUT') : tr('LABEL_NOTE_IN'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: isOut ? tr('HINT_NOTE_OUT') : tr('HINT_NOTE_IN'),
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

                // Lokalizacja w magazynie (regał + półka) — tylko przy przyjęciu.
                if (!isOut) ...[
                  const SizedBox(height: 8),
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
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z]')),
                            TextInputFormatter.withFunction((o, n) =>
                                n.copyWith(text: n.text.toUpperCase())),
                          ],
                          decoration: InputDecoration(
                            labelText: tr('LOCATION_RACK'),
                            labelStyle: const TextStyle(color: Colors.white54),
                            hintText: tr('LOCATION_HINT_RACK'),
                            hintStyle: const TextStyle(color: Colors.white24),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                            prefixIcon:
                                const Icon(Icons.shelves, color: _accent),
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
                            prefixIcon:
                                const Icon(Icons.layers, color: _accent),
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
                ],

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
                      : Icon(isOut ? Icons.remove_circle : Icons.add_circle,
                          color: Colors.white),
                  label: Text(
                    _isSaving
                        ? tr('BUTTON_SAVING')
                        : isOut
                            ? tr('BUTTON_ISSUE_GOODS')
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

                // Historia przedmiotów
                if (_movements.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Divider(color: Colors.white.withAlpha(30)),
                  Text(
                    tr('FORM_RECENT_MOVEMENTS'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70),
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
                        color: isIn
                            ? Colors.green.shade400
                            : Colors.orange.shade400,
                        size: 20,
                      ),
                      title: Text(
                        '${isIn ? '+' : '-'}${_formatQty(qty)} $unit',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIn
                              ? Colors.green.shade300
                              : Colors.orange.shade300,
                        ),
                      ),
                      subtitle: note != null && note.isNotEmpty
                          ? Text(note,
                              style: const TextStyle(color: Colors.white38))
                          : null,
                      trailing: Text(
                        _formatDate(date),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white24),
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

/// Dialog z wyszukiwarką kierowców
class _DriverSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> drivers;
  final void Function(int id, String name) onSelected;

  const _DriverSearchDialog({required this.drivers, required this.onSelected});

  @override
  State<_DriverSearchDialog> createState() => _DriverSearchDialogState();
}

class _DriverSearchDialogState extends State<_DriverSearchDialog> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  static const Color _accent = Color(0xFF3498DB);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);

  @override
  void initState() {
    super.initState();
    _filtered = widget.drivers;
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.drivers;
      } else {
        _filtered = widget.drivers
            .where((d) => (d['name'] as String).toLowerCase().contains(q))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('HINT_SEARCH_DRIVER'),
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
                      borderSide: BorderSide.none),
                  filled: true,
                  fillColor: _inputBg,
                ),
                onChanged: _filter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_filtered.length} ${tr('LABEL_DRIVERS_COUNT')}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        tr('LABEL_NO_RESULTS'),
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final d = _filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _accent.withAlpha(40),
                            child: Text(
                              (d['name'] as String)
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: _accent, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            d['name'] as String,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            widget.onSelected(
                                d['id'] as int, d['name'] as String);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
