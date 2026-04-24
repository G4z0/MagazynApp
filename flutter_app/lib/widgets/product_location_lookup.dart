import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

Future<void> showProductLocationLookup(BuildContext context) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2F3A),
      title: Text(
        tr('LOCATION_LOOKUP_TITLE'),
        style: const TextStyle(color: Colors.white),
      ),
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
          prefixIcon: const Icon(Icons.search, color: AppColors.accent),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            tr('BUTTON_CANCEL'),
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          child: Text(
            tr('BUTTON_SEARCH'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
  ctrl.dispose();

  if (code == null || code.isEmpty || !context.mounted) return;

  Map<String, dynamic>? product;
  String? errorMessage;
  try {
    product = await ApiService.getProductLocation(code);
  } on NetworkException catch (e) {
    errorMessage = e.message;
  } on ApiException catch (e) {
    errorMessage = e.message;
  }

  if (!context.mounted) return;

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
          code,
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

  final locations = _extractLocations(product);
  final pname = product['product_name'] ?? tr('PRODUCT_NO_NAME');
  final pbarcode = product['barcode']?.toString() ?? code;

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

String _formatLocationsSummary(List<Map<String, dynamic>> locations) {
  if (locations.isEmpty) return tr('LOCATION_NONE');
  return locations
      .map((location) => _formatLocation(location['rack'], location['shelf']))
      .whereType<String>()
      .join(', ');
}
