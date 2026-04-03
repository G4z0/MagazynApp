import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/workshop_api_service.dart';

/// Formularz dodania naprawy po zeskanowaniu tablicy rejestracyjnej.
class RepairFormScreen extends StatefulWidget {
  /// Dane pojazdu/naczepy znalezionego po tablicy.
  final Map<String, dynamic> vehicle;

  const RepairFormScreen({super.key, required this.vehicle});

  @override
  State<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends State<RepairFormScreen> {
  static const Color _accent = Color(0xFF3498DB);
  static const Color _darkBg = Color(0xFF1C1E26);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);
  static const Color _secondaryText = Color(0xFFA0A5B1);

  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  final _mileageController = TextEditingController();
  final _laborCostController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _serviceGroups = [];
  int? _selectedEmployeeId;
  DateTime _selectedDate = DateTime.now();
  final Map<int, bool> _selectedServices = {};
  final Map<int, TextEditingController> _serviceAmountControllers = {};
  final Map<int, TextEditingController> _serviceNoteControllers = {};

  // Custom services
  final List<_CustomService> _customServices = [];

  // Wykorzystane części
  final List<_SelectedPart> _selectedParts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _mileageController.dispose();
    _laborCostController.dispose();
    for (final c in _serviceAmountControllers.values) {
      c.dispose();
    }
    for (final c in _serviceNoteControllers.values) {
      c.dispose();
    }
    for (final cs in _customServices) {
      cs.nameController.dispose();
      cs.amountController.dispose();
      cs.noteController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final objectType = widget.vehicle['object_type'] as int;
    final results = await Future.wait([
      WorkshopApiService.getEmployees(),
      WorkshopApiService.getServiceGroups(objectType),
    ]);
    if (mounted) {
      setState(() {
        _employees = results[0] as List<Map<String, dynamic>>;
        _serviceGroups = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            surface: _cardBg,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _addCustomService() {
    setState(() {
      _customServices.add(_CustomService(
        nameController: TextEditingController(),
        amountController: TextEditingController(),
        noteController: TextEditingController(),
      ));
    });
  }

  void _removeCustomService(int index) {
    final cs = _customServices.removeAt(index);
    cs.nameController.dispose();
    cs.amountController.dispose();
    cs.noteController.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz pracownika'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    // Zbierz wybrane usługi
    final services = <Map<String, dynamic>>[];
    for (final entry in _selectedServices.entries) {
      if (entry.value) {
        services.add({
          'id': entry.key,
          'amount': double.tryParse(_serviceAmountControllers[entry.key]?.text ?? '') ?? 0,
          'note': _serviceNoteControllers[entry.key]?.text ?? '',
        });
      }
    }

    // Zbierz custom services
    final customServices = <Map<String, dynamic>>[];
    for (final cs in _customServices) {
      final name = cs.nameController.text.trim();
      if (name.isNotEmpty) {
        customServices.add({
          'name': name,
          'amount': double.tryParse(cs.amountController.text) ?? 0,
          'note': cs.noteController.text.trim(),
        });
      }
    }

    final result = await WorkshopApiService.addRepair(
      objectId: widget.vehicle['id'] as int,
      objectType: widget.vehicle['object_type'] as int,
      date: dateStr,
      employeeId: _selectedEmployeeId!,
      mileage: int.tryParse(_mileageController.text) ?? 0,
      laborCost: double.tryParse(_laborCostController.text) ?? 0,
      note: _noteController.text.trim(),
      userId: AuthService().userId ?? 0,
      services: services.isNotEmpty ? services : null,
      customServices: customServices.isNotEmpty ? customServices : null,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      await LocalHistoryService().add(
        actionType: 'repair_add',
        title: 'Dodano naprawę: ${widget.vehicle['plate']}',
        subtitle: '${widget.vehicle['object_label']}',
        userName: AuthService().displayName,
      );
      if (!mounted) return;
      _showSuccessDialog(result['message'] ?? 'Naprawa dodana');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Błąd zapisu'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Sukces!', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: _darkBg,
        foregroundColor: Colors.white,
        title: const Text('Nowa naprawa'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Karta pojazdu/naczepy
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _accent.withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _accent.withAlpha(60)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _accent.withAlpha(40),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            v['object_type'] == 2 ? Icons.rv_hookup : Icons.local_shipping,
                            color: _accent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v['plate'] ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                v['object_label'] ?? '',
                                style: const TextStyle(color: _secondaryText, fontSize: 13),
                              ),
                              if (v['vin'] != null && (v['vin'] as String).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'VIN: ${v['vin']}',
                                    style: TextStyle(color: _secondaryText.withAlpha(120), fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Data naprawy
                  _sectionLabel('Data naprawy'),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _inputBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: _accent, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit, color: _secondaryText, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pracownik
                  _sectionLabel('Pracownik *'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _inputBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonFormField<int>(
                      value: _selectedEmployeeId,
                      isExpanded: true,
                      dropdownColor: _cardBg,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.person, color: _accent),
                        hintText: 'Wybierz pracownika',
                        hintStyle: TextStyle(color: _secondaryText),
                      ),
                      items: _employees.map((e) {
                        final name = '${e['firstname']} ${e['lastname']}';
                        return DropdownMenuItem<int>(
                          value: int.tryParse(e['id'].toString()),
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedEmployeeId = v),
                      validator: (v) => v == null ? 'Wymagane' : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Przebieg
                  _sectionLabel('Przebieg (km)'),
                  _buildTextField(
                    controller: _mileageController,
                    icon: Icons.speed,
                    hint: '0',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),

                  // Koszt robocizny
                  _sectionLabel('Koszt robocizny (PLN)'),
                  _buildTextField(
                    controller: _laborCostController,
                    icon: Icons.payments,
                    hint: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),

                  // Usługi warsztatowe
                  if (_serviceGroups.isNotEmpty) ...[
                    _sectionLabel('Usługi warsztatowe'),
                    ..._serviceGroups.map((group) => _buildServiceGroup(group)),
                    const SizedBox(height: 8),
                  ],

                  // Custom services
                  Row(
                    children: [
                      _sectionLabel('Usługi własne'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addCustomService,
                        icon: const Icon(Icons.add, size: 18, color: _accent),
                        label: const Text('Dodaj', style: TextStyle(color: _accent)),
                      ),
                    ],
                  ),
                  ..._customServices.asMap().entries.map((entry) => _buildCustomService(entry.key, entry.value)),
                  const SizedBox(height: 16),

                  // Wykorzystane części
                  Row(
                    children: [
                      _sectionLabel('Wykorzystane części'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showPartsSearchDialog,
                        icon: const Icon(Icons.add, size: 18, color: _accent),
                        label: const Text('Dodaj', style: TextStyle(color: _accent)),
                      ),
                    ],
                  ),
                  if (_selectedParts.isNotEmpty)
                    ..._selectedParts.asMap().entries.map((entry) => _buildSelectedPart(entry.key, entry.value)),
                  if (_selectedParts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('Brak wybranych części', style: TextStyle(color: _secondaryText, fontSize: 13)),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Notatka
                  _sectionLabel('Notatka'),
                  _buildTextField(
                    controller: _noteController,
                    icon: Icons.note,
                    hint: 'Opis naprawy, uwagi...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  // Przycisk zapisu
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _accent.withAlpha(80),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.build, color: Colors.white),
                      label: Text(
                        _isSaving ? 'Zapisywanie...' : 'Dodaj naprawę',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(text, style: const TextStyle(color: _secondaryText, fontSize: 13, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _accent),
        hintText: hint,
        hintStyle: const TextStyle(color: _secondaryText),
        filled: true,
        fillColor: _inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildServiceGroup(Map<String, dynamic> group) {
    final groupName = group['name'] as String? ?? '';
    final services = List<Map<String, dynamic>>.from(group['services'] ?? []);
    if (services.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        iconColor: _secondaryText,
        collapsedIconColor: _secondaryText,
        title: Text(groupName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        children: services.map((svc) {
          final svcId = svc['id'] as int;
          final svcName = svc['name'] as String? ?? '';
          _selectedServices.putIfAbsent(svcId, () => false);
          _serviceAmountControllers.putIfAbsent(svcId, () => TextEditingController());
          _serviceNoteControllers.putIfAbsent(svcId, () => TextEditingController());
          final isSelected = _selectedServices[svcId] == true;

          return Column(
            children: [
              CheckboxListTile(
                value: isSelected,
                activeColor: _accent,
                contentPadding: EdgeInsets.zero,
                title: Text(svcName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                onChanged: (v) => setState(() => _selectedServices[svcId] = v ?? false),
                dense: true,
              ),
              if (isSelected) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _serviceAmountControllers[svcId],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Kwota PLN',
                            hintStyle: TextStyle(color: _secondaryText.withAlpha(120), fontSize: 12),
                            filled: true,
                            fillColor: _inputBg,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _serviceNoteControllers[svcId],
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Notatka',
                            hintStyle: TextStyle(color: _secondaryText.withAlpha(120), fontSize: 12),
                            filled: true,
                            fillColor: _inputBg,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        }).toList(),
      ),
    );
  }

  // ────────── Części ──────────

  void _showPartsSearchDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _darkBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => _PartsSearchSheet(
          scrollController: scrollCtrl,
          alreadySelected: _selectedParts.map((p) => '${p.barcode}_${p.unit}').toSet(),
          onPartSelected: (part) {
            setState(() {
              _selectedParts.add(part);
            });
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  Widget _buildSelectedPart(int index, _SelectedPart part) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              part.name,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // -/+ controls
          Container(
            decoration: BoxDecoration(
              color: _inputBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _qtyButton(Icons.remove, () {
                  if (part.quantity > 1) {
                    setState(() => part.quantity--);
                  }
                }),
                SizedBox(
                  width: 44,
                  child: TextField(
                    controller: TextEditingController(text: _fmtQty(part.quantity)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val > 0 && val <= part.maxStock) {
                        part.quantity = val;
                      }
                    },
                  ),
                ),
                _qtyButton(Icons.add, () {
                  if (part.quantity < part.maxStock) {
                    setState(() => part.quantity++);
                  }
                }),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => setState(() => _selectedParts.removeAt(index)),
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: _accent, size: 18),
      ),
    );
  }

  String _fmtQty(double v) {
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  Widget _buildCustomService(int index, _CustomService cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cs.nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Nazwa usługi',
                    hintStyle: const TextStyle(color: _secondaryText, fontSize: 13),
                    filled: true,
                    fillColor: _inputBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeCustomService(index),
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cs.amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Kwota PLN',
                    hintStyle: TextStyle(color: _secondaryText.withAlpha(120), fontSize: 12),
                    filled: true,
                    fillColor: _inputBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: cs.noteController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Notatka',
                    hintStyle: TextStyle(color: _secondaryText.withAlpha(120), fontSize: 12),
                    filled: true,
                    fillColor: _inputBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomService {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController noteController;

  _CustomService({
    required this.nameController,
    required this.amountController,
    required this.noteController,
  });
}

class _SelectedPart {
  final String barcode;
  final String name;
  final String unit;
  final double maxStock;
  double quantity;

  _SelectedPart({
    required this.barcode,
    required this.name,
    required this.unit,
    required this.maxStock,
    this.quantity = 1,
  });
}

/// Bottom sheet z wyszukiwaniem dostępnych części.
class _PartsSearchSheet extends StatefulWidget {
  final ScrollController scrollController;
  final Set<String> alreadySelected;
  final void Function(_SelectedPart part) onPartSelected;

  const _PartsSearchSheet({
    required this.scrollController,
    required this.alreadySelected,
    required this.onPartSelected,
  });

  @override
  State<_PartsSearchSheet> createState() => _PartsSearchSheetState();
}

class _PartsSearchSheetState extends State<_PartsSearchSheet> {
  static const Color _accent = Color(0xFF3498DB);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _inputBg = Color(0xFF23262E);
  static const Color _secondaryText = Color(0xFFA0A5B1);

  List<Map<String, dynamic>> _parts = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadParts({String search = ''}) async {
    setState(() => _isLoading = true);
    final parts = await ApiService.getAvailableParts(search: search);
    if (mounted) {
      setState(() {
        _parts = parts;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadParts(search: value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Wybierz część',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Szukaj po nazwie lub kodzie...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: _inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        const SizedBox(height: 8),
        // Results
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : _parts.isEmpty
                  ? const Center(
                      child: Text('Brak dostępnych części',
                          style: TextStyle(color: Colors.white38)),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: _parts.length,
                      itemBuilder: (_, i) {
                        final p = _parts[i];
                        final barcode = p['barcode'] ?? '';
                        final name = p['product_name'] ?? 'Bez nazwy';
                        final unit = p['unit'] ?? 'szt';
                        final stock = double.tryParse(p['current_stock'].toString()) ?? 0;
                        final key = '${barcode}_$unit';
                        final alreadyAdded = widget.alreadySelected.contains(key);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: alreadyAdded ? _cardBg.withAlpha(100) : _cardBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: alreadyAdded ? Colors.white38 : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$barcode  ·  ${_fmtQty(stock)} $unit',
                              style: const TextStyle(color: _secondaryText, fontSize: 11),
                            ),
                            trailing: alreadyAdded
                                ? const Icon(Icons.check, color: Colors.green, size: 20)
                                : Icon(Icons.add_circle_outline, color: _accent, size: 22),
                            onTap: alreadyAdded
                                ? null
                                : () {
                                    widget.onPartSelected(_SelectedPart(
                                      barcode: barcode,
                                      name: name,
                                      unit: unit,
                                      maxStock: stock,
                                    ));
                                  },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _fmtQty(double v) {
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }
}
