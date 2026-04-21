import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../models/code_type.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';
import 'scanner_screen.dart';

/// Model pozycji wydania w trybie wsadowym.
class _IssueItem {
  String barcode;
  String productName;
  double quantity;
  String unit;
  CodeType codeType;
  String? note;
  String? location;
  bool isLoading;
  bool isIssued;
  String? error;

  _IssueItem({
    required this.barcode,
    this.productName = '',
    this.quantity = 1,
    this.unit = 'szt',
    required this.codeType,
    this.note,
    this.location,
    this.isLoading = false,
    this.isIssued = false,
    this.error,
  });
}

/// Ekran wsadowego wydawania produktów.
///
/// Pozwala dodać wiele pozycji (skan / ręcznie) i wydać je
/// jednym przyciskiem, ustawiając wspólne dane (powód, cel) raz.
class BatchIssueScreen extends StatefulWidget {
  const BatchIssueScreen({super.key});

  @override
  State<BatchIssueScreen> createState() => _BatchIssueScreenState();
}

class _BatchIssueScreenState extends State<BatchIssueScreen> {
  final List<_IssueItem> _items = [];
  bool _isSubmitting = false;

  // Wspólne dane wydania
  String _issueReason = 'departure';
  String _issueTarget = 'vehicle';
  final _vehiclePlateController = TextEditingController();
  List<Map<String, dynamic>> _drivers = [];
  int? _selectedDriverId;
  String? _selectedDriverName;
  bool _isLoadingDrivers = false;

  static const Color _accent = Color(0xFF3498DB);
  static const Color _darkBg = Color(0xFF1C1E26);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    _vehiclePlateController.dispose();
    super.dispose();
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

  /// Otwórz skaner i dodaj zeskanowany produkt do listy.
  Future<void> _scanAndAdd() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(returnBarcodeOnly: true),
      ),
    );
    if (barcode == null || barcode.isEmpty || !mounted) return;

    // Zapytaj o ilość przed dodaniem do listy.
    final qty = await _promptScanQuantity(barcode);
    if (qty == null || qty <= 0 || !mounted) return;

    _addItemByBarcode(barcode, quantity: qty);
  }

  /// Dialog wyboru ilości tuż po skanowaniu (- / + / wpis ręczny).
  Future<double?> _promptScanQuantity(String barcode) async {
    double qty = 1;
    final controller = TextEditingController(text: '1');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          void setQty(double v) {
            if (v < 1) v = 1;
            qty = v;
            controller.text = _formatQty(v);
            controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length));
            setStateDialog(() {});
          }

          return AlertDialog(
            backgroundColor: _cardBg,
            title: Text(tr('BATCH_QTY_DIALOG_TITLE'),
                style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(barcode,
                    style: const TextStyle(
                        color: Colors.white60,
                        fontFamily: 'monospace',
                        fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => setQty(qty - 1),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputBg,
                          hintText: tr('BATCH_QTY_DIALOG_HINT'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12),
                        ),
                        onChanged: (v) {
                          final parsed =
                              double.tryParse(v.replaceAll(',', '.'));
                          if (parsed != null && parsed > 0) qty = parsed;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: () => setQty(qty + 1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('BUTTON_CANCEL')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () {
                  final parsed =
                      double.tryParse(controller.text.replaceAll(',', '.'));
                  Navigator.pop(
                      ctx, (parsed != null && parsed > 0) ? parsed : qty);
                },
                child: Text(tr('BUTTON_ADD')),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  /// Pokaż bottom sheet z listą produktów do wyboru.
  void _showProductPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProductPickerSheet(
        onSelected: (barcode, productName, unit, stock, location) {
          // Sprawdź duplikat — przy trafieniu zwiększ ilość i przesuń na górę.
          final existingIndex = _items.indexWhere(
              (i) => i.barcode == barcode && i.unit == unit && !i.isIssued);
          if (existingIndex != -1) {
            setState(() {
              final existing = _items.removeAt(existingIndex);
              existing.quantity += 1;
              _items.insert(0, existing);
            });
            _showSnackBar(tr('BATCH_ITEM_QTY_INCREASED'));
            return;
          }
          setState(() {
            _items.insert(
              0,
              _IssueItem(
                barcode: barcode,
                productName: productName,
                quantity: 1,
                unit: unit,
                codeType: CodeType.detect(barcode),
                location: location,
              ),
            );
          });
        },
      ),
    );
  }

  /// Dodaj pozycję na podstawie kodu i pobierz dane z API.
  Future<void> _addItemByBarcode(String barcode, {double quantity = 1}) async {
    // Sprawdź czy ten kod już jest na liście — zwiększ ilość i przesuń na górę.
    final existingIndex =
        _items.indexWhere((i) => i.barcode == barcode && !i.isIssued);
    if (existingIndex != -1) {
      setState(() {
        final existing = _items.removeAt(existingIndex);
        existing.quantity += quantity;
        _items.insert(0, existing);
      });
      _showSnackBar(tr('BATCH_ITEM_QTY_INCREASED'));
      return;
    }

    final codeType = CodeType.detect(barcode);
    final item = _IssueItem(
      barcode: barcode,
      codeType: codeType,
      quantity: quantity,
      isLoading: true,
    );
    setState(() => _items.insert(0, item));

    // Pobierz dane z API
    try {
      final result = await ApiService.checkBarcode(barcode);
      if (!mounted) return;
      setState(() {
        item.isLoading = false;
        if (result != null) {
          final data = result['data'] as Map<String, dynamic>?;
          if (data != null) {
            item.productName = data['product_name'] as String? ?? '';
            if (data['code_type'] != null) {
              item.codeType = CodeType.fromApi(data['code_type'] as String);
            }
            // Lokalizacja w magazynie (regał + półka).
            final rack = (data['location_rack'] as String?)?.trim();
            final shelf = data['location_shelf'];
            if (rack != null && rack.isNotEmpty && shelf != null) {
              item.location = '$rack$shelf';
            }
          }
          // Ustaw jednostkę z pierwszego stanu magazynowego
          if (result['stock'] != null) {
            final stockList = List<Map<String, dynamic>>.from(
              (result['stock'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)),
            );
            if (stockList.isNotEmpty) {
              item.unit = stockList.first['unit'] as String? ?? 'szt';
            }
          }
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => item.isLoading = false);
      }
    }
  }

  /// Usuń pozycję z listy.
  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  /// Wydaj wszystkie pozycje z listy.
  Future<void> _submitAll() async {
    // Walidacja wspólnych pól
    if (_issueTarget == 'vehicle' &&
        _vehiclePlateController.text.trim().isEmpty) {
      _showSnackBar(tr('VALIDATION_VEHICLE_REQUIRED'));
      return;
    }
    if (_issueTarget == 'driver' && _selectedDriverId == null) {
      _showSnackBar(tr('VALIDATION_DRIVER_REQUIRED'));
      return;
    }

    final pendingItems = _items.where((i) => !i.isIssued).toList();
    if (pendingItems.isEmpty) return;

    // Walidacja pozycji
    for (final item in pendingItems) {
      if (item.productName.trim().isEmpty) {
        _showSnackBar(tr('BATCH_VALIDATION_NAME_REQUIRED'));
        return;
      }
      if (item.quantity <= 0) {
        _showSnackBar(tr('VALIDATION_QUANTITY_POSITIVE'));
        return;
      }
    }

    setState(() => _isSubmitting = true);

    int successCount = 0;
    int failCount = 0;

    for (final item in pendingItems) {
      try {
        await ApiService.saveProduct(
          barcode: item.barcode,
          productName: item.productName,
          quantity: item.quantity,
          unit: item.unit,
          codeType: item.codeType,
          movementType: 'out',
          note: item.note,
          issueReason: _issueReason,
          vehiclePlate: _issueTarget == 'vehicle'
              ? _vehiclePlateController.text.trim()
              : null,
          issueTarget: _issueTarget,
          driverId: _issueTarget == 'driver' ? _selectedDriverId : null,
          driverName: _issueTarget == 'driver' ? _selectedDriverName : null,
        );

        await LocalHistoryService().add(
          actionType: 'stock_out',
          title: '${tr('LOG_STOCK_OUT')}: ${item.productName}',
          subtitle:
              '${_formatQty(item.quantity)} ${item.unit} — ${item.barcode}',
          barcode: item.barcode,
          quantity: item.quantity,
          unit: item.unit,
          userName: AuthService().displayName,
        );

        if (mounted) {
          setState(() {
            item.isIssued = true;
            item.error = null;
          });
        }
        successCount++;
      } on NetworkException {
        await OfflineQueueService().enqueue(
          barcode: item.barcode,
          productName: item.productName,
          quantity: item.quantity,
          unit: item.unit,
          codeType: item.codeType,
          movementType: 'out',
          note: item.note,
          issueReason: _issueReason,
          vehiclePlate: _issueTarget == 'vehicle'
              ? _vehiclePlateController.text.trim()
              : null,
          issueTarget: _issueTarget,
          driverId: _issueTarget == 'driver' ? _selectedDriverId : null,
          driverName: _issueTarget == 'driver' ? _selectedDriverName : null,
        );

        await LocalHistoryService().add(
          actionType: 'stock_out',
          title: '${tr('LOG_STOCK_OUT')} (offline): ${item.productName}',
          subtitle:
              '${_formatQty(item.quantity)} ${item.unit} — ${item.barcode}',
          barcode: item.barcode,
          quantity: item.quantity,
          unit: item.unit,
          userName: AuthService().displayName,
        );

        if (mounted) {
          setState(() {
            item.isIssued = true;
            item.error = null;
          });
        }
        successCount++;
      } on ApiException catch (e) {
        if (mounted) {
          setState(() => item.error = e.message);
        }
        failCount++;
      } catch (e) {
        await OfflineQueueService().enqueue(
          barcode: item.barcode,
          productName: item.productName,
          quantity: item.quantity,
          unit: item.unit,
          codeType: item.codeType,
          movementType: 'out',
          note: item.note,
          issueReason: _issueReason,
          vehiclePlate: _issueTarget == 'vehicle'
              ? _vehiclePlateController.text.trim()
              : null,
          issueTarget: _issueTarget,
          driverId: _issueTarget == 'driver' ? _selectedDriverId : null,
          driverName: _issueTarget == 'driver' ? _selectedDriverName : null,
        );

        await LocalHistoryService().add(
          actionType: 'stock_out',
          title: '${tr('LOG_STOCK_OUT')} (offline): ${item.productName}',
          subtitle:
              '${_formatQty(item.quantity)} ${item.unit} — ${item.barcode}',
          barcode: item.barcode,
          quantity: item.quantity,
          unit: item.unit,
          userName: AuthService().displayName,
        );

        if (mounted) {
          setState(() {
            item.isIssued = true;
            item.error = null;
          });
        }
        successCount++;
      }
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
      _showResultDialog(successCount, failCount);
    }
  }

  void _showResultDialog(int success, int fail) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        icon: Icon(
          fail == 0 ? Icons.check_circle : Icons.warning,
          color: fail == 0 ? Colors.green : Colors.orange,
          size: 48,
        ),
        title: Text(
          fail == 0 ? tr('DIALOG_SUCCESS_TITLE') : tr('BATCH_PARTIAL_SUCCESS'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          tr('BATCH_RESULT_MESSAGE',
              args: {'success': '$success', 'fail': '$fail'}),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          if (fail > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('BUTTON_RETRY'),
                  style: const TextStyle(color: Colors.white54)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              if (fail == 0) {
                Navigator.pop(context);
              }
            },
            child:
                Text(fail == 0 ? tr('BUTTON_CONFIRM') : tr('BUTTON_CONFIRM')),
          ),
        ],
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  static const List<({String value, String key})> _unitOptions = [
    (value: 'szt', key: 'UNIT_PIECES'),
    (value: 'opak', key: 'UNIT_PACKAGES'),
    (value: 'l', key: 'UNIT_LITRES'),
    (value: 'kg', key: 'UNIT_KILOGRAMS'),
    (value: 'm', key: 'UNIT_METRES'),
    (value: 'kpl', key: 'UNIT_SETS'),
  ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = _items.where((i) => !i.isIssued).length;
    final issuedCount = _items.where((i) => i.isIssued).length;

    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        title: Text(tr('BATCH_ISSUE_TITLE')),
        centerTitle: true,
        backgroundColor: _darkBg,
        foregroundColor: Colors.white,
        actions: [
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  '$pendingCount',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.orange.shade800,
                side: BorderSide.none,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Wspólne ustawienia wydania
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- Sekcja: Wspólne dane wydania ---
                  Container(
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.settings,
                                color: Colors.orange.shade400, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              tr('BATCH_COMMON_SETTINGS'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Powód wydania
                        Text(
                          tr('LABEL_ISSUE_REASON'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            expandedInsets: EdgeInsets.zero,
                            segments: [
                              ButtonSegment(
                                value: 'departure',
                                label: Text(tr('ISSUE_DEPARTURE'),
                                    style: const TextStyle(fontSize: 12)),
                                icon:
                                    const Icon(Icons.departure_board, size: 18),
                              ),
                              ButtonSegment(
                                value: 'replacement',
                                label: Text(tr('ISSUE_REPLACEMENT'),
                                    style: const TextStyle(fontSize: 12)),
                                icon: const Icon(Icons.swap_horiz, size: 18),
                              ),
                            ],
                            selected: {_issueReason},
                            onSelectionChanged: (value) {
                              setState(() => _issueReason = value.first);
                            },
                            style: ButtonStyle(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.orange.shade800.withAlpha(180);
                                }
                                return _inputBg;
                              }),
                              foregroundColor:
                                  WidgetStateProperty.all(Colors.white),
                              side: WidgetStateProperty.all(BorderSide(
                                  color: Colors.white.withAlpha(30))),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Cel wydania
                        Text(
                          tr('LABEL_ISSUE_TARGET'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            expandedInsets: EdgeInsets.zero,
                            segments: [
                              ButtonSegment(
                                value: 'vehicle',
                                label: Text(tr('ISSUE_TO_VEHICLE'),
                                    style: const TextStyle(fontSize: 12)),
                                icon:
                                    const Icon(Icons.local_shipping, size: 18),
                              ),
                              ButtonSegment(
                                value: 'driver',
                                label: Text(tr('ISSUE_TO_DRIVER'),
                                    style: const TextStyle(fontSize: 12)),
                                icon: const Icon(Icons.person, size: 18),
                              ),
                              ButtonSegment(
                                value: 'workshop',
                                label: Text(tr('ISSUE_TO_WORKSHOP'),
                                    style: const TextStyle(fontSize: 12)),
                                icon: const Icon(Icons.build, size: 18),
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
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.blue.shade800.withAlpha(180);
                                }
                                return _inputBg;
                              }),
                              foregroundColor:
                                  WidgetStateProperty.all(Colors.white),
                              side: WidgetStateProperty.all(BorderSide(
                                  color: Colors.white.withAlpha(30))),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Samochód
                        if (_issueTarget == 'vehicle')
                          TextField(
                            controller: _vehiclePlateController,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: tr('LABEL_VEHICLE_PLATE'),
                              labelStyle:
                                  const TextStyle(color: Colors.white54),
                              hintText: tr('HINT_VEHICLE_PLATE'),
                              hintStyle: const TextStyle(color: Colors.white24),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              prefixIcon: const Icon(Icons.local_shipping,
                                  color: _accent),
                              filled: true,
                              fillColor: _inputBg,
                            ),
                            maxLength: 20,
                          ),

                        // Kierowca
                        if (_issueTarget == 'driver')
                          _isLoadingDrivers
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: _accent)),
                                )
                              : GestureDetector(
                                  onTap: _showDriverSearchDialog,
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
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- Sekcja: Lista pozycji ---
                  Row(
                    children: [
                      Icon(Icons.list_alt,
                          color: Colors.orange.shade400, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('BATCH_ITEMS_LIST'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (issuedCount > 0)
                        Text(
                          tr('BATCH_ISSUED_COUNT',
                              args: {'count': '$issuedCount'}),
                          style: TextStyle(
                              color: Colors.green.shade400, fontSize: 13),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 48, color: Colors.white.withAlpha(40)),
                          const SizedBox(height: 12),
                          Text(
                            tr('BATCH_EMPTY_LIST'),
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_items.length, (index) {
                      final item = _items[index];
                      return _buildItemCard(item, index);
                    }),

                  const SizedBox(height: 16),

                  // Przyciski dodawania
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSubmitting ? null : _showProductPicker,
                          icon: const Icon(Icons.add_circle_outline),
                          label: Text(tr('BATCH_ADD_FROM_LIST')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: BorderSide(color: _accent.withAlpha(120)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSubmitting ? null : _scanAndAdd,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(tr('BATCH_SCAN_ADD')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withAlpha(40)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Dolny pasek z przyciskiem wydania
          if (pendingCount > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: _cardBg,
                border:
                    Border(top: BorderSide(color: Colors.white.withAlpha(20))),
              ),
              child: SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitAll,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                  label: Text(
                    _isSubmitting
                        ? tr('BUTTON_SAVING')
                        : tr('BATCH_ISSUE_ALL',
                            args: {'count': '$pendingCount'}),
                    style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.orange.shade800,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemCard(_IssueItem item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: item.isIssued
            ? Colors.green.shade900.withAlpha(60)
            : item.error != null
                ? Colors.red.shade900.withAlpha(60)
                : _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isIssued
              ? Colors.green.shade700.withAlpha(80)
              : item.error != null
                  ? Colors.red.shade700.withAlpha(80)
                  : Colors.white.withAlpha(15),
        ),
      ),
      child: item.isLoading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2)),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nagłówek: nazwa + przycisk usunięcia
                  Row(
                    children: [
                      Icon(
                        item.isIssued ? Icons.check_circle : Icons.inventory_2,
                        color: item.isIssued ? Colors.green.shade400 : _accent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.productName.isNotEmpty
                              ? item.productName
                              : item.barcode,
                          style: TextStyle(
                            color: item.isIssued
                                ? Colors.green.shade300
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            decoration: item.isIssued
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (item.location != null && !item.isIssued) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accent.withAlpha(40),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _accent.withAlpha(120)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.pin_drop,
                                  color: _accent, size: 11),
                              const SizedBox(width: 2),
                              Text(
                                item.location!,
                                style: const TextStyle(
                                  color: _accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!item.isIssued && !_isSubmitting)
                        IconButton(
                          icon: Icon(Icons.close,
                              color: Colors.red.shade400, size: 20),
                          onPressed: () => _removeItem(index),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Kod kreskowy
                  Text(
                    item.barcode,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),

                  // Błąd
                  if (item.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.error!,
                      style:
                          TextStyle(color: Colors.red.shade400, fontSize: 12),
                    ),
                  ],

                  // Ilość (edytowalna tylko gdy nie wydano)
                  if (!item.isIssued) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Minus
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton.filled(
                            onPressed: item.quantity > 1
                                ? () => setState(() => item.quantity -= 1)
                                : null,
                            icon: const Icon(Icons.remove, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: _inputBg,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _inputBg.withAlpha(80),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Ilość
                        SizedBox(
                          width: 64,
                          child: TextField(
                            controller: TextEditingController(
                                text: _formatQty(item.quantity)),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                              filled: true,
                              fillColor: _inputBg,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10),
                            ),
                            onChanged: (v) {
                              final qty = double.tryParse(v);
                              if (qty != null && qty > 0) {
                                item.quantity = qty;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Plus
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton.filled(
                            onPressed: () => setState(() => item.quantity += 1),
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: _inputBg,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item.unit,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: item.note ?? ''),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: tr('LABEL_NOTE'),
                        hintStyle: const TextStyle(
                            color: Colors.white24, fontSize: 13),
                        prefixIcon: const Icon(Icons.notes,
                            color: Colors.white38, size: 18),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: _inputBg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) =>
                          item.note = v.trim().isEmpty ? null : v.trim(),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatQty(item.quantity)} ${item.unit}',
                      style:
                          TextStyle(color: Colors.green.shade300, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Dialog z wyszukiwarką kierowców (kopia z ProductFormScreen).
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
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(tr('LABEL_NO_RESULTS'),
                          style: const TextStyle(color: Colors.white38)),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final driver = _filtered[i];
                        final id = driver['id'] as int;
                        final name = driver['name'] as String;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _accent.withAlpha(50),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: _accent),
                            ),
                          ),
                          title: Text(name,
                              style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            widget.onSelected(id, name);
                            Navigator.pop(ctx);
                          },
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

/// Bottom sheet z listą produktów do wyboru (z wyszukiwarką).
class _ProductPickerSheet extends StatefulWidget {
  final void Function(String barcode, String productName, String unit,
      double stock, String? location) onSelected;

  const _ProductPickerSheet({required this.onSelected});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _allParts = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;

  static const Color _accent = Color(0xFF3498DB);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  Future<void> _loadParts() async {
    try {
      final parts = await ApiService.getAvailableParts();
      if (mounted) {
        setState(() {
          _allParts = parts;
          _filtered = parts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = _allParts;
      } else {
        _filtered = _allParts.where((p) {
          final name = (p['product_name'] as String? ?? '').toLowerCase();
          final barcode = (p['barcode'] as String? ?? '').toLowerCase();
          return name.contains(q) || barcode.contains(q);
        }).toList();
      }
    });
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Uchwyt
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Nagłówek
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('BATCH_PICK_PRODUCT'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Szukajka
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('PARTS_SEARCH_HINT'),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} ${tr('PRODUCT_PLURAL_MANY')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
            // Lista
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(tr('LABEL_NO_RESULTS'),
                              style: const TextStyle(color: Colors.white38)),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final part = _filtered[i];
                            final barcode = part['barcode'] as String? ?? '';
                            final name = part['product_name'] as String? ??
                                tr('PRODUCT_NO_NAME');
                            final unit = part['unit'] as String? ?? 'szt';
                            final stock = double.tryParse(
                                    part['current_stock'].toString()) ??
                                0;
                            final rack =
                                (part['location_rack'] as String?)?.trim();
                            final shelf = part['location_shelf'];
                            final hasLocation = rack != null &&
                                rack.isNotEmpty &&
                                shelf != null;
                            final locationLabel = hasLocation
                                ? '$rack${shelf is int ? shelf : int.tryParse(shelf.toString()) ?? shelf}'
                                : null;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _accent.withAlpha(40),
                                child: const Icon(Icons.inventory_2,
                                    color: _accent, size: 20),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (locationLabel != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _accent.withAlpha(40),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: _accent.withAlpha(120)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.pin_drop,
                                              color: _accent, size: 11),
                                          const SizedBox(width: 2),
                                          Text(
                                            locationLabel,
                                            style: const TextStyle(
                                              color: _accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '$barcode  •  ${_formatQty(stock)} $unit',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                              trailing: Icon(Icons.add_circle_outline,
                                  color: Colors.green.shade400),
                              onTap: () {
                                widget.onSelected(
                                    barcode, name, unit, stock, locationLabel);
                                Navigator.pop(ctx);
                              },
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
