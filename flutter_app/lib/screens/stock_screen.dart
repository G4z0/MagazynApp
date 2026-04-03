import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../services/api_service.dart';

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
                  onPressed: _isLoading ? null : () => _loadProducts(search: _searchController.text.trim()),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              onPressed: () => _loadProducts(search: _searchController.text.trim()),
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
                  ? tr('STOCK_NO_RESULTS', args: {'query': _searchController.text})
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
    final currentStock = double.tryParse(product['current_stock'].toString()) ?? 0;
    final totalIn = double.tryParse(product['total_in'].toString()) ?? 0;
    final totalOut = double.tryParse(product['total_out'].toString()) ?? 0;
    final lastMovement = product['last_movement'] as String?;
    final isLow = currentStock <= 0;

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
        child: Padding(
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
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  Future<void> _showProductDetail(String barcode) async {
    final result = await ApiService.checkBarcode(barcode);
    if (!mounted || result == null) return;

    final data = result['data'] as Map<String, dynamic>?;
    final movements = result['movements'] as List? ?? [];

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
              Text(
                data['product_name'] ?? tr('PRODUCT_NO_NAME'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
              const SizedBox(height: 16),
            ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                        style:
                            const TextStyle(color: Colors.white24, fontSize: 11),
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
