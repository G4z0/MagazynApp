import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../theme/app_theme.dart';
import 'app_ui.dart';

class DriverSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> drivers;
  final void Function(int id, String name) onSelected;

  const DriverSearchDialog({
    super.key,
    required this.drivers,
    required this.onSelected,
  });

  @override
  State<DriverSearchDialog> createState() => _DriverSearchDialogState();
}

class _DriverSearchDialogState extends State<DriverSearchDialog> {
  final _searchController = TextEditingController();
  late List<Map<String, dynamic>> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.drivers;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.drivers
          : widget.drivers
              .where(
                  (d) => (d['name'] as String? ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
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
                decoration: appInputDecoration(
                  label: tr('HINT_SEARCH_DRIVER'),
                  icon: Icons.search,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38),
                          onPressed: () {
                            _searchController.clear();
                            _filter('');
                          },
                        )
                      : null,
                ),
                onChanged: _filter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} ${tr('LABEL_DRIVERS_COUNT')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                        final driver = _filtered[i];
                        final id = driver['id'] as int;
                        final name = driver['name'] as String? ?? '';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.accent.withAlpha(40),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(color: Colors.white),
                          ),
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
