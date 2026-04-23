import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../models/code_type.dart';
import 'scanner_screen.dart';
import '../services/api_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';

class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({
    super.key,
    required this.barcode,
    required this.productName,
    required this.codeType,
    this.locations = const [],
    this.stockByUnit = const [],
  });

  final String barcode;
  final String productName;
  final CodeType codeType;
  final List<Map<String, dynamic>> locations;
  final List stockByUnit;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  static const Color accent = Color(0xFF3498DB);
  static const Color cardBg = Color(0xFF2C2F3A);
  static const Color sheetBg = Color(0xFF1C1E26);

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  final List<_LocationDraft> _locationDrafts = [];

  final Map<String, TextEditingController> _qtyCtrls = {};
  final Map<String, double> _currentQtys = {};
  final TextEditingController _qtyReasonCtrl = TextEditingController();

  bool _isSaving = false;
  late String _currentBarcode;
  late String _currentProductName;
  late CodeType _currentCodeType;
  late List<Map<String, dynamic>> _currentLocations;

  @override
  void initState() {
    super.initState();
    _currentBarcode = widget.barcode;
    _currentProductName = widget.productName;
    _currentCodeType = widget.codeType;
    _nameCtrl = TextEditingController(text: widget.productName);
    _barcodeCtrl = TextEditingController(text: widget.barcode);

    _currentLocations = _normalizeLocations(widget.locations);
    if (_currentLocations.isEmpty) {
      _locationDrafts.add(_LocationDraft());
    } else {
      for (final location in _currentLocations) {
        _locationDrafts.add(_LocationDraft.fromLocation(location));
      }
    }

    for (final s in widget.stockByUnit) {
      final m = Map<String, dynamic>.from(s as Map);
      final unit = (m['unit'] as String?) ?? 'szt';
      final cur = double.tryParse(m['current_stock'].toString()) ?? 0;
      _currentQtys[unit] = cur;
      _qtyCtrls[unit] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _qtyReasonCtrl.dispose();
    for (final draft in _locationDrafts) {
      draft.dispose();
    }
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  List<Map<String, dynamic>> _normalizeLocations(List locations) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final raw in locations) {
      final location = Map<String, dynamic>.from(raw as Map);
      final rack = location['rack']?.toString().trim().toUpperCase();
      final shelf = int.tryParse(location['shelf'].toString());
      if (rack == null || rack.isEmpty || shelf == null) continue;
      final key = '$rack#$shelf';
      if (seen.add(key)) {
        result.add({'rack': rack, 'shelf': shelf});
      }
    }

    return result;
  }

  String _locationsSignature(List<Map<String, dynamic>> locations) =>
      locations.map((location) => '${location['rack']}#${location['shelf']}').join('|');

  String _locationsSummary(List<Map<String, dynamic>> locations) {
    if (locations.isEmpty) {
      return tr('LOCATION_NONE');
    }
    return locations
        .map((location) => '${location['rack']}${location['shelf']}')
        .join(', ');
  }

  List<Map<String, dynamic>> _collectLocations() {
    final locations = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final draft in _locationDrafts) {
      final rack = draft.rackCtrl.text.trim().toUpperCase();
      final shelfRaw = draft.shelfCtrl.text.trim();

      if (rack.isEmpty && shelfRaw.isEmpty) {
        continue;
      }
      if (rack.isEmpty || shelfRaw.isEmpty) {
        throw ApiException(tr('LOCATION_VALIDATION_BOTH_REQUIRED'));
      }
      if (!RegExp(r'^[A-Z]{1,2}$').hasMatch(rack)) {
        throw ApiException(tr('LOCATION_VALIDATION_RACK'));
      }

      final shelf = int.tryParse(shelfRaw);
      if (shelf == null || shelf < 0 || shelf > 99) {
        throw ApiException(tr('LOCATION_VALIDATION_SHELF'));
      }

      final key = '$rack#$shelf';
      if (!seen.add(key)) {
        throw ApiException(tr('LOCATION_VALIDATION_DUPLICATE'));
      }

      locations.add({'rack': rack, 'shelf': shelf});
    }

    return locations;
  }

  void _addLocationRow() {
    setState(() {
      _locationDrafts.add(_LocationDraft());
    });
  }

  void _removeLocationRow(int index) {
    final removed = _locationDrafts.removeAt(index);
    removed.dispose();
    if (_locationDrafts.isEmpty) {
      _locationDrafts.add(_LocationDraft());
    }
    setState(() {});
  }

  Future<bool> _confirmBarcodeChange(String oldB, String newB) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 40),
        title: Text(
          tr('EDIT_BARCODE_CONFIRM_TITLE'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('EDIT_BARCODE_CONFIRM_BODY'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    oldB,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const Icon(Icons.arrow_downward,
                      color: Colors.white38, size: 16),
                  Text(
                    newB,
                    style: const TextStyle(
                      color: accent,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('BUTTON_CANCEL'),
                style: const TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('BUTTON_CONFIRM'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  void _applyIdentityData(
    Map<String, dynamic> data, {
    required String fallbackBarcode,
    required String fallbackProductName,
    required CodeType fallbackCodeType,
  }) {
    final barcode = (data['barcode'] as String?)?.trim();
    final productName = (data['product_name'] as String?)?.trim();
    final codeType = data['code_type'] as String?;

    _currentBarcode =
        (barcode != null && barcode.isNotEmpty) ? barcode : fallbackBarcode;
    _currentProductName = (productName != null && productName.isNotEmpty)
        ? productName
        : fallbackProductName;
    _currentCodeType =
        codeType != null ? CodeType.fromApi(codeType) : fallbackCodeType;

    _barcodeCtrl.value = TextEditingValue(
      text: _currentBarcode,
      selection: TextSelection.collapsed(offset: _currentBarcode.length),
    );
    _nameCtrl.value = TextEditingValue(
      text: _currentProductName,
      selection: TextSelection.collapsed(offset: _currentProductName.length),
    );
  }

  Future<void> _scanBarcode() async {
    if (_isSaving) return;

    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(returnBarcodeOnly: true),
      ),
    );

    if (!mounted || barcode == null) return;

    final scannedCode = barcode.trim();
    if (scannedCode.isEmpty) return;

    _barcodeCtrl.value = TextEditingValue(
      text: scannedCode,
      selection: TextSelection.collapsed(offset: scannedCode.length),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final newName = _nameCtrl.text.trim();
    final newBarcode = _barcodeCtrl.text.trim();

    late final List<Map<String, dynamic>> newLocations;
    try {
      newLocations = _collectLocations();
    } on ApiException catch (e) {
      _showSnack(e.message, color: Colors.red.shade700);
      return;
    }

    final nameChanged = newName != _currentProductName;
    final barcodeChanged = newBarcode != _currentBarcode;
    final locChanged =
        _locationsSignature(newLocations) != _locationsSignature(_currentLocations);

    final corrections = <_QtyCorrection>[];
    for (final entry in _qtyCtrls.entries) {
      final raw = entry.value.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) continue;
      final parsed = double.tryParse(raw);
      if (parsed == null || parsed < 0) {
        _showSnack(tr('EDIT_QTY_VALIDATION'), color: Colors.red.shade700);
        return;
      }
      final cur = _currentQtys[entry.key] ?? 0;
      final diff = parsed - cur;
      if (diff == 0) continue;
      corrections.add(
        _QtyCorrection(unit: entry.key, delta: diff, targetValue: parsed),
      );
    }

    if (!nameChanged && !barcodeChanged && !locChanged && corrections.isEmpty) {
      Navigator.pop(context, false);
      return;
    }

    if (barcodeChanged) {
      final ok = await _confirmBarcodeChange(_currentBarcode, newBarcode);
      if (!ok) return;
    }

    if (corrections.isNotEmpty && _qtyReasonCtrl.text.trim().isEmpty) {
      _showSnack(tr('EDIT_QTY_REASON_REQUIRED'), color: Colors.red.shade700);
      return;
    }

    setState(() => _isSaving = true);
    var didChange = false;

    try {
      if (barcodeChanged) {
        final oldBarcode = _currentBarcode;
        try {
          final data = await ApiService.changeBarcode(
            oldBarcode: _currentBarcode,
            newBarcode: newBarcode,
            newName: newName,
          );
          _applyIdentityData(
            data,
            fallbackBarcode: newBarcode,
            fallbackProductName: newName,
            fallbackCodeType: CodeType.detect(newBarcode),
          );
          didChange = true;
          await LocalHistoryService().add(
            actionType: 'edit_barcode',
            title: tr('EDIT_BARCODE_LOG_TITLE'),
            subtitle: '$oldBarcode → $_currentBarcode',
            barcode: _currentBarcode,
          );
        } on NetworkException catch (e) {
          _showSnack(e.message, color: Colors.red.shade700);
          return;
        } on ApiException catch (e) {
          _showSnack(e.message, color: Colors.red.shade700);
          return;
        }
      } else if (nameChanged) {
        try {
          final data = await ApiService.renameProduct(
            barcode: _currentBarcode,
            newName: newName,
          );
          _applyIdentityData(
            data,
            fallbackBarcode: _currentBarcode,
            fallbackProductName: newName,
            fallbackCodeType: _currentCodeType,
          );
          didChange = true;
        } on NetworkException catch (e) {
          _showSnack(e.message, color: Colors.red.shade700);
          return;
        } on ApiException catch (e) {
          _showSnack(e.message, color: Colors.red.shade700);
          return;
        }
      }

      if (locChanged) {
        try {
          await ApiService.setProductLocations(
            barcode: _currentBarcode,
            locations: newLocations,
          );
          didChange = true;
          await LocalHistoryService().add(
            actionType: 'set_location',
            title: tr('LOCATION_EDIT_TITLE'),
            subtitle: _locationsSummary(newLocations),
            barcode: _currentBarcode,
          );
          _currentLocations = _normalizeLocations(newLocations);
        } on NetworkException {
          await OfflineQueueService().enqueueSetLocations(
            barcode: _currentBarcode,
            locations: newLocations,
          );
          _showSnack(tr('LOCATION_QUEUED'), color: Colors.orange.shade800);
          _currentLocations = _normalizeLocations(newLocations);
          didChange = true;
        } on ApiException catch (e) {
          _showSnack(e.message, color: Colors.red.shade700);
          return;
        }
      }

      if (corrections.isNotEmpty) {
        final reason = _qtyReasonCtrl.text.trim();
        for (final c in corrections) {
          final note = '${tr('EDIT_QTY_NOTE_PREFIX')}: $reason';
          final movementType = c.delta > 0 ? 'in' : 'out';
          final qty = c.delta.abs();
          final previousQty = _currentQtys[c.unit] ?? 0;

          try {
            await ApiService.saveProduct(
              barcode: _currentBarcode,
              productName: _currentProductName,
              quantity: qty,
              unit: c.unit,
              codeType: _currentCodeType,
              movementType: movementType,
              note: note,
            );
            didChange = true;
            _currentQtys[c.unit] = c.targetValue;
            _qtyCtrls[c.unit]?.clear();
            await LocalHistoryService().add(
              actionType: 'qty_correction',
              title: tr('EDIT_QTY_LOG_TITLE'),
              subtitle:
                  '${c.unit}: ${_formatQty(previousQty)} → ${_formatQty(c.targetValue)}',
              barcode: _currentBarcode,
              quantity: qty,
              unit: c.unit,
            );
          } on NetworkException {
            await OfflineQueueService().enqueue(
              barcode: _currentBarcode,
              productName: _currentProductName,
              quantity: qty,
              unit: c.unit,
              codeType: _currentCodeType,
              movementType: movementType,
              note: note,
            );
            _showSnack(tr('EDIT_QTY_QUEUED'), color: Colors.orange.shade800);
            _currentQtys[c.unit] = c.targetValue;
            _qtyCtrls[c.unit]?.clear();
            didChange = true;
          } on ApiException catch (e) {
            _showSnack(e.message, color: Colors.red.shade700);
            return;
          }
        }
      }

      if (didChange && mounted) {
        _showSnack(tr('EDIT_SAVED_SUCCESS'), color: Colors.green.shade700);
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sheetBg,
      appBar: AppBar(
        backgroundColor: sheetBg,
        title: Text(tr('EDIT_PRODUCT_TITLE'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildSectionTitle(tr('EDIT_SECTION_BASIC')),
            _buildCard([
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                maxLength: 255,
                decoration: _inputDecoration(
                  label: tr('LABEL_PRODUCT_NAME'),
                  icon: Icons.label,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return tr('VALIDATION_PRODUCT_NAME_REQUIRED');
                  if (t.length < 2) {
                    return tr('VALIDATION_PRODUCT_NAME_MIN_LENGTH');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcodeCtrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
                maxLength: 128,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._\-]')),
                ],
                decoration: _inputDecoration(
                  label: tr('EDIT_BARCODE_LABEL'),
                  icon: Icons.qr_code,
                  helper: tr('EDIT_BARCODE_HELPER'),
                  suffixIcon: IconButton(
                    onPressed: _isSaving ? null : _scanBarcode,
                    tooltip: tr('TILE_SCAN_CODE'),
                    icon: const Icon(Icons.qr_code_scanner, color: accent),
                  ),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return tr('EDIT_BARCODE_VALIDATION');
                  return null;
                },
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionTitle(tr('EDIT_SECTION_LOCATION')),
            _buildCard([
              Text(
                tr('LOCATION_MULTI_HELPER'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...List.generate(_locationDrafts.length, (index) {
                final draft = _locationDrafts[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: draft.rackCtrl,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(2),
                            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) =>
                                  newValue.copyWith(text: newValue.text.toUpperCase()),
                            ),
                          ],
                          decoration: _inputDecoration(
                            label: '${tr('LOCATION_RACK')} ${index + 1}',
                            icon: Icons.view_column,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: draft.shelfCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(2),
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: _inputDecoration(
                            label: '${tr('LOCATION_SHELF')} ${index + 1}',
                            icon: Icons.layers,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _locationDrafts.length == 1
                            ? () {
                                draft.rackCtrl.clear();
                                draft.shelfCtrl.clear();
                                setState(() {});
                              }
                            : () => _removeLocationRow(index),
                        icon: const Icon(Icons.delete_outline, color: Colors.white54),
                        tooltip: tr('LOCATION_REMOVE_BUTTON'),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addLocationRow,
                  icon: const Icon(Icons.add, color: accent),
                  label: Text(
                    tr('LOCATION_ADD_BUTTON'),
                    style: const TextStyle(color: accent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: accent.withAlpha(160)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionTitle(tr('EDIT_SECTION_QTY_CORRECTION')),
            if (_qtyCtrls.isEmpty)
              _buildCard([
                Text(
                  tr('EDIT_QTY_NO_UNITS'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ])
            else
              _buildCard([
                Text(
                  tr('EDIT_QTY_HELPER'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ..._qtyCtrls.entries.map((e) {
                  final cur = _currentQtys[e.key] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.key,
                                style: const TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${tr('FORM_STOCK_LEVEL')} ${_formatQty(cur)}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: e.value,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            decoration: _inputDecoration(
                              label: tr('EDIT_QTY_NEW'),
                              icon: Icons.edit,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _qtyReasonCtrl,
                  style: const TextStyle(color: Colors.white),
                  maxLength: 200,
                  decoration: _inputDecoration(
                    label: tr('EDIT_QTY_REASON'),
                    icon: Icons.notes,
                    helper: tr('EDIT_QTY_REASON_HELPER'),
                  ),
                ),
              ]),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(
                tr('BUTTON_SAVE'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _buildCard(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? helper,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      helperText: helper,
      helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
      helperMaxLines: 2,
      filled: true,
      fillColor: sheetBg,
      prefixIcon: Icon(icon, color: accent, size: 20),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      counterStyle: const TextStyle(color: Colors.white24, fontSize: 10),
    );
  }
}

class _QtyCorrection {
  final String unit;
  final double delta;
  final double targetValue;

  _QtyCorrection({
    required this.unit,
    required this.delta,
    required this.targetValue,
  });
}

class _LocationDraft {
  _LocationDraft({String? rack, String? shelf})
      : rackCtrl = TextEditingController(text: rack ?? ''),
        shelfCtrl = TextEditingController(text: shelf ?? '');

  factory _LocationDraft.fromLocation(Map<String, dynamic> location) {
    return _LocationDraft(
      rack: location['rack']?.toString(),
      shelf: location['shelf']?.toString(),
    );
  }

  final TextEditingController rackCtrl;
  final TextEditingController shelfCtrl;

  void dispose() {
    rackCtrl.dispose();
    shelfCtrl.dispose();
  }
}
