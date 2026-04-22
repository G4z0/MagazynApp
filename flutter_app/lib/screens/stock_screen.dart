import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../services/api_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';
import 'product_form_screen.dart';

/// Ekran stanów magazynowych — lista produktów z aktualnym stanem.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  static const Color accent = Color(0xFF3498DB);
  static const Color cardBg = Color(0xFF2C2F3A);
  static const Color secondaryText = Color(0xFFA0A5B1);

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts({String search = ''}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final products = await ApiService.getStockList(search: search);
      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = tr('ERROR_SERVER_CONNECTION');
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadProducts(search: value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('STOCK_TITLE'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _showLocationLookupDialog,
                  icon: const Icon(Icons.pin_drop, color: accent),
                  tooltip: tr('TOOLTIP_CHECK_LOCATION'),
                ),
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _loadProducts(search: _searchController.text.trim()),
                  icon: Icon(
                    Icons.refresh,
                    color: _isLoading ? Colors.white24 : accent,
                  ),
                  tooltip: tr('BUTTON_REFRESH'),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: tr('STOCK_SEARCH_HINT'),
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          _loadProducts();
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Product count
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${_products.length} ${_pluralProducts(_products.length)}',
                style: const TextStyle(color: secondaryText, fontSize: 13),
              ),
            ),

          // Content
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () =>
                  _loadProducts(search: _searchController.text.trim()),
              icon: const Icon(Icons.refresh),
              label: Text(tr('BUTTON_RETRY')),
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2, color: Colors.white24, size: 64),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isNotEmpty
                  ? tr('STOCK_NO_RESULTS',
                      args: {'query': _searchController.text})
                  : tr('STOCK_EMPTY'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: accent,
      onRefresh: () => _loadProducts(search: _searchController.text.trim()),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _products.length,
        itemBuilder: (context, index) => _buildProductCard(_products[index]),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final name = product['product_name'] ?? tr('PRODUCT_NO_NAME');
    final barcode = product['barcode'] ?? '';
    final unit = product['unit'] ?? 'szt';
    final currentStock =
        double.tryParse(product['current_stock'].toString()) ?? 0;
    final totalIn = double.tryParse(product['total_in'].toString()) ?? 0;
    final totalOut = double.tryParse(product['total_out'].toString()) ?? 0;
    final lastMovement = product['last_movement'] as String?;
    final minQuantityRaw = product['min_quantity'];
    final double? minQuantity = (minQuantityRaw == null)
        ? null
        : (double.tryParse(minQuantityRaw.toString()) ?? 0);
    final bool hasMin = minQuantity != null && minQuantity > 0;
    final isLow = hasMin ? currentStock < minQuantity : currentStock <= 0;
    final locationLabel =
        _formatLocation(product['location_rack'], product['location_shelf']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: isLow ? Border.all(color: Colors.red.shade800, width: 1) : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProductDetail(barcode),
        child: Stack(
          children: [
            // Lokalizacja — chip w prawym górnym rogu karty.
            if (locationLabel != null)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withAlpha(120)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pin_drop, color: accent, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        locationLabel,
                        style: const TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Stock badge
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isLow
                          ? Colors.red.withAlpha(25)
                          : accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatQty(currentStock),
                            style: TextStyle(
                              color: isLow ? Colors.red.shade300 : accent,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            unit,
                            style: TextStyle(
                              color: isLow ? Colors.red.shade300 : accent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Product info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                              right: locationLabel != null ? 80 : 0),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          barcode,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.add_circle_outline,
                                color: Colors.green.shade400, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              '${_formatQty(totalIn)} $unit',
                              style: TextStyle(
                                  color: Colors.green.shade400, fontSize: 11),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.remove_circle_outline,
                                color: Colors.red.shade400, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              '${_formatQty(totalOut)} $unit',
                              style: TextStyle(
                                  color: Colors.red.shade400, fontSize: 11),
                            ),
                            if (lastMovement != null) ...[
                              const Spacer(),
                              Text(
                                _formatDate(lastMovement),
                                style: const TextStyle(
                                    color: Colors.white24, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isLow ? Icons.warning_amber : Icons.chevron_right,
                    color: isLow ? Colors.red.shade300 : Colors.white24,
                    size: 22,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductDetail(String barcode) async {
    final result = await ApiService.checkBarcode(barcode);
    if (!mounted || result == null) return;

    final data = result['data'] as Map<String, dynamic>?;
    final movements = result['movements'] as List? ?? [];
    final stockList = result['stock'] as List? ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1E26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (data != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      data['product_name'] ?? tr('PRODUCT_NO_NAME'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showRenameDialog(
                        barcode,
                        data['product_name'] ?? '',
                      );
                    },
                    icon: const Icon(Icons.edit, color: accent, size: 20),
                    tooltip: tr('STOCK_RENAME_PRODUCT'),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditLocationDialog(
                        barcode,
                        data['location_rack'] as String?,
                        data['location_shelf'] is int
                            ? data['location_shelf'] as int?
                            : (data['location_shelf'] != null
                                ? int.tryParse(
                                    data['location_shelf'].toString())
                                : null),
                      );
                    },
                    icon: const Icon(Icons.pin_drop, color: accent, size: 20),
                    tooltip: tr('STOCK_EDIT_LOCATION'),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                data['barcode'] ?? '',
                style: const TextStyle(
                  color: Colors.white38,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              if (_formatLocation(
                      data['location_rack'], data['location_shelf']) !=
                  null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.pin_drop, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${tr('LOCATION_LABEL')}: ',
                      style:
                          const TextStyle(color: secondaryText, fontSize: 13),
                    ),
                    Text(
                      _formatLocation(
                              data['location_rack'], data['location_shelf']) ??
                          '',
                      style: const TextStyle(
                        color: accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
            // Sekcja minimalnych stanów (per jednostka)
            if (data != null && stockList.isNotEmpty) ...[
              ...stockList.map((s) {
                final m = Map<String, dynamic>.from(s as Map);
                final unit = m['unit'] as String? ?? 'szt';
                final cur =
                    double.tryParse(m['current_stock'].toString()) ?? 0;
                final minRaw = m['min_quantity'];
                final double? minVal = (minRaw == null)
                    ? null
                    : (double.tryParse(minRaw.toString()) ?? 0);
                final bool hasMin = minVal != null && minVal > 0;
                final bool low = hasMin ? cur < minVal : false;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: low
                          ? Border.all(color: Colors.red.shade800, width: 1)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          low ? Icons.warning_amber : Icons.warning_amber,
                          size: 18,
                          color: low ? Colors.red.shade300 : Colors.white38,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasMin
                                ? "${tr('LABEL_MIN_STOCK')}: ${_formatQty(minVal)} $unit"
                                : "${tr('LABEL_MIN_STOCK')}: ${tr('MIN_STOCK_NOT_SET')} ($unit)",
                            style: TextStyle(
                              color: low ? Colors.red.shade300 : Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditMinStockDialog(barcode, unit, minVal);
                          },
                          icon: const Icon(Icons.edit,
                              size: 16, color: accent),
                          label: Text(
                            hasMin ? tr('BUTTON_EDIT') : tr('BUTTON_SET'),
                            style: const TextStyle(
                                color: accent, fontSize: 13),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
            // Przycisk Wydaj
            if (data != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductFormScreen(
                          barcode: barcode,
                          initialMovementType: 'out',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.remove_circle, color: Colors.white),
                  label: Text(
                    tr('BUTTON_ISSUE_GOODS'),
                    style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.orange.shade800,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            if (movements.isNotEmpty) ...[
              Text(
                tr('STOCK_ITEM_HISTORY'),
                style: const TextStyle(color: secondaryText, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...movements.map((m) {
                final isIn = m['movement_type'] == 'in';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isIn
                              ? Colors.green.withAlpha(30)
                              : Colors.red.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isIn ? Icons.add : Icons.remove,
                          color: isIn
                              ? Colors.green.shade400
                              : Colors.red.shade400,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${isIn ? '+' : '-'}${_formatQty(m['quantity'])} ${m['unit']}',
                              style: TextStyle(
                                color: isIn
                                    ? Colors.green.shade300
                                    : Colors.red.shade300,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (m['note'] != null &&
                                (m['note'] as String).isNotEmpty)
                              Text(
                                m['note'],
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(m['created_at']),
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 11),
                      ),
                    ],
                  ),
                );
              }),
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(tr('STOCK_NO_MOVEMENTS'),
                      style: const TextStyle(color: Colors.white38)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(String barcode, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2F3A),
        title: Text(
          tr('STOCK_RENAME_PRODUCT'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: tr('STOCK_RENAME_HINT'),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1C1E26),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('BUTTON_CANCEL'),
                style: const TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(ctx, value);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: Text(tr('BUTTON_SAVE'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName == currentName) return;

    final success =
        await ApiService.renameProduct(barcode: barcode, newName: newName);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('STOCK_RENAME_SUCCESS')),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _loadProducts(search: _searchController.text.trim());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('STOCK_RENAME_ERROR')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String? _formatLocation(dynamic rack, dynamic shelf) {
    if (rack == null || shelf == null) return null;
    final rackStr = rack.toString().trim();
    if (rackStr.isEmpty) return null;
    final shelfInt = shelf is int ? shelf : int.tryParse(shelf.toString());
    if (shelfInt == null) return null;
    return '$rackStr$shelfInt';
  }

  Future<void> _showEditLocationDialog(
    String barcode,
    String? currentRack,
    int? currentShelf,
  ) async {
    final result = await showDialog<({String? rack, int? shelf})>(
      context: context,
      builder: (ctx) => _LocationEditDialog(
        initialRack: currentRack,
        initialShelf: currentShelf,
        accent: accent,
      ),
    );

    if (result == null) return;
    final rack = result.rack;
    final shelf = result.shelf;

    try {
      await ApiService.setProductLocation(
          barcode: barcode, rack: rack, shelf: shelf);
      await LocalHistoryService().add(
        actionType: 'set_location',
        title: tr('LOCATION_EDIT_TITLE'),
        subtitle: '${rack ?? '-'}${shelf ?? ''} — $barcode',
        barcode: barcode,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('LOCATION_SAVED')),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _loadProducts(search: _searchController.text.trim());
      }
    } on NetworkException {
      await OfflineQueueService().enqueueSetLocation(
        barcode: barcode,
        rack: rack,
        shelf: shelf,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('LOCATION_QUEUED')),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _showEditMinStockDialog(
    String barcode,
    String unit,
    double? currentValue,
  ) async {
    final controller = TextEditingController(
      text: (currentValue == null || currentValue <= 0)
          ? ''
          : (currentValue == currentValue.roundToDouble()
              ? currentValue.toInt().toString()
              : currentValue.toString()),
    );
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2F3A),
        title: Text(
          tr('MIN_STOCK_EDIT_TITLE'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$barcode  ($unit)',
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: tr('LABEL_MIN_STOCK'),
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: tr('HINT_MIN_STOCK_OPTIONAL'),
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1C1E26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                prefixIcon:
                    const Icon(Icons.warning_amber, color: accent),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              tr('BUTTON_CANCEL'),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          if (currentValue != null && currentValue > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: Text(
                tr('MIN_STOCK_REMOVE'),
                style: TextStyle(color: Colors.red.shade300),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: Text(
              tr('BUTTON_SAVE'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (action == null) {
      controller.dispose();
      return;
    }

    double? newValue;
    if (action == 'save') {
      final raw = controller.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) {
        newValue = null; // pusty zapis = usunięcie
      } else {
        final parsed = double.tryParse(raw);
        if (parsed == null || parsed < 0) {
          controller.dispose();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr('MIN_STOCK_VALIDATION')),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return;
        }
        newValue = parsed;
      }
    } else {
      // remove
      newValue = null;
    }
    controller.dispose();

    try {
      await ApiService.setMinQuantity(
        barcode: barcode,
        unit: unit,
        minQuantity: newValue,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('MIN_STOCK_SAVED')),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _loadProducts(search: _searchController.text.trim());
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } on NetworkException {
      await OfflineQueueService().enqueueSetMinQuantity(
        barcode: barcode,
        unit: unit,
        minQuantity: newValue,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('MIN_STOCK_QUEUED')),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
  }

  Future<void> _showLocationLookupDialog() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2F3A),
        title: Text(tr('LOCATION_LOOKUP_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: tr('LOCATION_LOOKUP_HINT'),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1C1E26),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(Icons.search, color: accent),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('BUTTON_CANCEL'),
                style: const TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: Text(tr('BUTTON_SEARCH'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (code == null || code.isEmpty || !mounted) return;

    Map<String, dynamic>? product;
    String? errorMessage;
    try {
      product = await ApiService.getProductLocation(code);
    } on NetworkException catch (e) {
      errorMessage = e.message;
    } on ApiException catch (e) {
      errorMessage = e.message;
    }

    if (!mounted) return;

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (product == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2C2F3A),
          icon: const Icon(Icons.search_off, color: Colors.orange, size: 40),
          title: Text(tr('LOCATION_LOOKUP_NOT_FOUND'),
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(code,
              style: const TextStyle(
                  color: Colors.white54, fontFamily: 'monospace')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: Text(tr('BUTTON_CONFIRM'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    final loc =
        _formatLocation(product['location_rack'], product['location_shelf']);
    final pname = product['product_name'] ?? tr('PRODUCT_NO_NAME');
    final pbarcode = product['barcode']?.toString() ?? code;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2F3A),
        icon: Icon(
          loc != null ? Icons.pin_drop : Icons.location_off,
          color: accent,
          size: 48,
        ),
        title: Text(pname,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pbarcode,
                style: const TextStyle(
                    color: Colors.white38,
                    fontFamily: 'monospace',
                    fontSize: 12)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withAlpha(80)),
              ),
              child: Text(
                loc ?? tr('LOCATION_NONE'),
                style: TextStyle(
                  color: loc != null ? accent : Colors.white54,
                  fontSize: loc != null ? 32 : 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: Text(tr('BUTTON_CONFIRM'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatQty(dynamic qty) {
    final v = double.tryParse(qty.toString()) ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr);
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _pluralProducts(int count) {
    if (count == 1) return tr('PRODUCT_SINGULAR');
    if (count >= 2 && count <= 4) return tr('PRODUCT_PLURAL_FEW');
    return tr('PRODUCT_PLURAL_MANY');
  }
}

/// Dialog edycji lokalizacji (regał + półka).
///
/// Wyodrębniony jako [StatefulWidget], żeby [TextEditingController]-y żyły
/// w [State] i były dispose'owane dopiero w [State.dispose()] — czyli już
/// po zakończeniu animacji zamykania dialogu. Wcześniej dispose tuż po
/// `Navigator.pop` powodował, że pola w jeszcze-zamykającym-się [Form]
/// odwoływały się do zwolnionych kontrolerów, co kończyło się
/// asercją `_dependents.isEmpty` w `InheritedElement.debugDeactivated`.
class _LocationEditDialog extends StatefulWidget {
  const _LocationEditDialog({
    required this.initialRack,
    required this.initialShelf,
    required this.accent,
  });

  final String? initialRack;
  final int? initialShelf;
  final Color accent;

  @override
  State<_LocationEditDialog> createState() => _LocationEditDialogState();
}

class _LocationEditDialogState extends State<_LocationEditDialog> {
  late final TextEditingController _rackCtrl;
  late final TextEditingController _shelfCtrl;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _rackCtrl = TextEditingController(text: widget.initialRack ?? '');
    _shelfCtrl =
        TextEditingController(text: widget.initialShelf?.toString() ?? '');
  }

  @override
  void dispose() {
    _rackCtrl.dispose();
    _shelfCtrl.dispose();
    super.dispose();
  }

  void _onSave() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final rackOut = _rackCtrl.text.trim().toUpperCase();
    final shelfOut = _shelfCtrl.text.trim();
    final String? rack = rackOut.isEmpty ? null : rackOut;
    final int? shelf = shelfOut.isEmpty ? null : int.tryParse(shelfOut);
    Navigator.pop<({String? rack, int? shelf})>(
        context, (rack: rack, shelf: shelf));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2F3A),
      title: Text(tr('LOCATION_EDIT_TITLE'),
          style: const TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _rackCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, letterSpacing: 2),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(2),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                  TextInputFormatter.withFunction(
                      (o, n) => n.copyWith(text: n.text.toUpperCase())),
                ],
                decoration: InputDecoration(
                  labelText: tr('LOCATION_RACK'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: tr('LOCATION_HINT_RACK'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF1C1E26),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  final rack = (v ?? '').trim();
                  final shelf = _shelfCtrl.text.trim();
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
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _shelfCtrl,
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
                  filled: true,
                  fillColor: const Color(0xFF1C1E26),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  final shelf = (v ?? '').trim();
                  final rack = _rackCtrl.text.trim();
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('BUTTON_CANCEL'),
              style: const TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          onPressed: _onSave,
          style: FilledButton.styleFrom(backgroundColor: widget.accent),
          child: Text(tr('BUTTON_SAVE'),
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
