import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../services/local_history_service.dart';

/// Ekran historii działań wykonanych NA TYM urządzeniu.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _accent = Color(0xFF3498DB);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _secondaryText = Color(0xFFA0A5B1);

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await LocalHistoryService().getHistory(limit: 200);
    if (mounted)
      setState(() {
        _items = items;
        _isLoading = false;
      });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text(tr('DIALOG_CLEAR_HISTORY_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Text(tr('DIALOG_CLEAR_HISTORY_CONTENT'),
            style: const TextStyle(color: _secondaryText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('BUTTON_CANCEL'),
                style: const TextStyle(color: _secondaryText)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('BUTTON_CLEAR')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LocalHistoryService().clear();
      _load();
    }
  }

  IconData _iconForAction(String type) {
    switch (type) {
      case 'stock_in':
        return Icons.add_circle;
      case 'stock_out':
        return Icons.remove_circle;
      case 'scan':
        return Icons.qr_code_scanner;
      case 'stock_check':
        return Icons.search;
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'repair_add':
        return Icons.build;
      default:
        return Icons.history;
    }
  }

  Color _colorForAction(String type) {
    switch (type) {
      case 'stock_in':
        return Colors.green;
      case 'stock_out':
        return Colors.orange;
      case 'scan':
        return _accent;
      case 'login':
        return _accent;
      case 'logout':
        return _secondaryText;
      case 'repair_add':
        return Colors.purple;
      default:
        return _secondaryText;
    }
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return tr('DATE_TODAY', args: {'time': time});
    if (diff == 1) return tr('DATE_YESTERDAY', args: {'time': time});
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} $time';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  tr('HISTORY_TITLE'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_items.isNotEmpty)
                  IconButton(
                    icon:
                        const Icon(Icons.delete_outline, color: _secondaryText),
                    onPressed: _clearHistory,
                    tooltip: tr('TOOLTIP_CLEAR_HISTORY'),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, color: Color(0xFFA0A5B1), size: 64),
            const SizedBox(height: 12),
            Text(tr('HISTORY_EMPTY_TITLE'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(tr('HISTORY_EMPTY_SUBTITLE'),
                style: const TextStyle(color: Color(0xFFA0A5B1), fontSize: 13)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final item = _items[i];
          final type = item['action_type'] as String? ?? '';
          final title = item['title'] as String? ?? '';
          final subtitle = item['subtitle'] as String?;
          final createdAt = item['created_at'] as String? ?? '';
          final userName = item['user_name'] as String?;

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _colorForAction(type).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconForAction(type),
                      color: _colorForAction(type), size: 20),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            style: const TextStyle(
                                color: _secondaryText, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          userName != null
                              ? '${_formatDate(createdAt)} • $userName'
                              : _formatDate(createdAt),
                          style: TextStyle(
                              color: _secondaryText.withAlpha(150),
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
