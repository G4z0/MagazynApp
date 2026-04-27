import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../screens/scanner_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'app_ui.dart';

enum _LocationLookupAction { scan, search }

Future<void> showProductLocationLookup(BuildContext context) async {
  final action = await _showLocationLookupActions(context);
  if (action == null || !context.mounted) return;

  switch (action) {
    case _LocationLookupAction.scan:
      await _scanAndShowLocation(context);
    case _LocationLookupAction.search:
      await _searchAndShowLocation(context);
  }
}

Future<_LocationLookupAction?> _showLocationLookupActions(
  BuildContext context,
) {
  return showModalBottomSheet<_LocationLookupAction>(
    context: context,
    backgroundColor: AppColors.darkBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppModalHandle(),
            Text(
              tr('LOCATION_LOOKUP_TITLE'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            _LocationActionTile(
              icon: Icons.qr_code_scanner,
              title: tr('LOCATION_LOOKUP_SCAN'),
              subtitle: tr('LOCATION_LOOKUP_SCAN_SUBTITLE'),
              onTap: () => Navigator.pop(ctx, _LocationLookupAction.scan),
            ),
            const SizedBox(height: 10),
            _LocationActionTile(
              icon: Icons.manage_search,
              title: tr('LOCATION_LOOKUP_SEARCH_NAME'),
              subtitle: tr('LOCATION_LOOKUP_SEARCH_SUBTITLE'),
              onTap: () => Navigator.pop(ctx, _LocationLookupAction.search),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _scanAndShowLocation(BuildContext context) async {
  final code = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => ScannerScreen(
        returnBarcodeOnly: true,
        title: tr('LOCATION_LOOKUP_TITLE'),
      ),
    ),
  );

  if (!context.mounted) return;
  await _showLocationByCode(context, code);
}

Future<void> _searchAndShowLocation(BuildContext context) async {
  final product = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.darkBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => _ProductLocationSearchSheet(
        scrollController: scrollController,
      ),
    ),
  );

  if (product == null || !context.mounted) return;

  final barcode = _stringValue(product['barcode']);
  if (barcode.isEmpty) {
    await _showProductLocationResult(context, product, fallbackCode: '');
    return;
  }

  await _showLocationByCode(
    context,
    barcode,
    fallbackProduct: product,
  );
}

Future<void> _showLocationByCode(
  BuildContext context,
  String? rawCode, {
  Map<String, dynamic>? fallbackProduct,
}) async {
  final lookupCode = rawCode?.trim();
  if (lookupCode == null || lookupCode.isEmpty || !context.mounted) return;

  Map<String, dynamic>? product;
  String? errorMessage;
  try {
    product = await ApiService.getProductLocation(lookupCode);
  } on NetworkException catch (e) {
    errorMessage = e.message;
  } on ApiException catch (e) {
    errorMessage = e.message;
  }

  if (!context.mounted) return;

  product ??= fallbackProduct;

  if (errorMessage != null && product == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red.shade700,
      ),
    );
    return;
  }

  if (product == null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2F3A),
        icon: const Icon(Icons.search_off, color: Colors.orange, size: 40),
        title: Text(
          tr('LOCATION_LOOKUP_NOT_FOUND'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          lookupCode,
          style:
              const TextStyle(color: Colors.white54, fontFamily: 'monospace'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            child: Text(
              tr('BUTTON_CONFIRM'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return;
  }

  await _showProductLocationResult(
    context,
    product,
    fallbackCode: lookupCode,
  );
}

Future<void> _showProductLocationResult(
  BuildContext context,
  Map<String, dynamic> product, {
  required String fallbackCode,
}) async {
  final locations = _extractLocations(product);
  final pname = _stringValue(product['product_name']).isNotEmpty
      ? _stringValue(product['product_name'])
      : tr('PRODUCT_NO_NAME');
  final pbarcode = _stringValue(product['barcode']).isNotEmpty
      ? _stringValue(product['barcode'])
      : fallbackCode;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2F3A),
      icon: Icon(
        locations.isNotEmpty ? Icons.pin_drop : Icons.location_off,
        color: AppColors.accent,
        size: 48,
      ),
      title: Text(
        pname,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pbarcode,
            style: const TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withAlpha(80)),
            ),
            child: locations.isEmpty
                ? Text(
                    tr('LOCATION_NONE'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : Text(
                    _formatLocationsSummary(locations),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 1.5,
                    ),
                  ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          child: Text(
            tr('BUTTON_CONFIRM'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _ProductLocationSearchSheet extends StatefulWidget {
  final ScrollController scrollController;

  const _ProductLocationSearchSheet({required this.scrollController});

  @override
  State<_ProductLocationSearchSheet> createState() =>
      _ProductLocationSearchSheetState();
}

class _ProductLocationSearchSheetState
    extends State<_ProductLocationSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() => _query = query);

    if (query.isEmpty) {
      setState(() {
        _products = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _loadProducts(query);
    });
  }

  Future<void> _loadProducts(String query) async {
    setState(() => _isLoading = true);
    final products = await ApiService.getStockList(search: query);
    if (!mounted || query != _controller.text.trim()) return;
    setState(() {
      _products = _dedupeByBarcode(products);
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> _dedupeByBarcode(
    List<Map<String, dynamic>> products,
  ) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final product in products) {
      final barcode = _stringValue(product['barcode']);
      final key = barcode.isEmpty ? product.toString() : barcode;
      if (seen.add(key)) unique.add(product);
    }
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppModalHandle(),
            Text(
              tr('LOCATION_LOOKUP_SEARCH_NAME'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: appInputDecoration(
                label: tr('STOCK_SEARCH_HINT'),
                icon: Icons.search,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.clear, color: Colors.white38),
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return _SheetMessage(
        icon: Icons.manage_search,
        title: tr('LOCATION_LOOKUP_SEARCH_EMPTY'),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (_products.isEmpty) {
      return _SheetMessage(
        icon: Icons.search_off,
        title: tr('LABEL_NO_RESULTS'),
      );
    }

    return ListView.separated(
      controller: widget.scrollController,
      itemCount: _products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = _products[index];
        final name = _stringValue(product['product_name']).isNotEmpty
            ? _stringValue(product['product_name'])
            : tr('PRODUCT_NO_NAME');
        final barcode = _stringValue(product['barcode']);
        final locations = _extractLocations(product);
        final locationChip = _formatLocationsChip(locations);

        return Material(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context, product),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withAlpha(28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          barcode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        if (locationChip != null) ...[
                          const SizedBox(height: 8),
                          LocationChip(label: locationChip),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.white24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LocationActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LocationActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SheetMessage({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 52),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

String _stringValue(dynamic value) => value?.toString().trim() ?? '';

String? _formatLocation(dynamic rack, dynamic shelf) {
  if (rack == null || shelf == null) return null;
  final rackStr = rack.toString().trim();
  if (rackStr.isEmpty) return null;
  final shelfInt = shelf is int ? shelf : int.tryParse(shelf.toString());
  if (shelfInt == null) return null;
  return '$rackStr$shelfInt';
}

List<Map<String, dynamic>> _extractLocations(Map<String, dynamic>? source) {
  if (source == null) return const [];

  final rawLocations = source['locations'];
  if (rawLocations is List) {
    final locations = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final raw in rawLocations) {
      if (raw is! Map) continue;
      final location = Map<String, dynamic>.from(raw);
      final rack = location['rack']?.toString().trim().toUpperCase();
      final shelf = int.tryParse(location['shelf'].toString());
      if (rack == null || rack.isEmpty || shelf == null) continue;
      final key = '$rack#$shelf';
      if (seen.add(key)) {
        locations.add({'rack': rack, 'shelf': shelf});
      }
    }

    if (locations.isNotEmpty) {
      return locations;
    }
  }

  final legacy =
      _formatLocation(source['location_rack'], source['location_shelf']);
  if (legacy == null) return const [];

  return [
    {
      'rack': source['location_rack']?.toString(),
      'shelf': int.tryParse(source['location_shelf'].toString()),
    }
  ];
}

String? _formatLocationsChip(List<Map<String, dynamic>> locations) {
  if (locations.isEmpty) return null;
  final first = _formatLocation(locations[0]['rack'], locations[0]['shelf']);
  if (first == null) return null;
  if (locations.length == 1) return first;
  return '$first +${locations.length - 1}';
}

String _formatLocationsSummary(List<Map<String, dynamic>> locations) {
  if (locations.isEmpty) return tr('LOCATION_NONE');
  return locations
      .map((location) => _formatLocation(location['rack'], location['shelf']))
      .whereType<String>()
      .join(', ');
}
