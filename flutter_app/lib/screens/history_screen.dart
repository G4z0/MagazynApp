import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../models/issue_target_preset.dart';
import '../services/local_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'scanner_screen.dart';

/// Ekran historii działań wykonanych NA TYM urządzeniu.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _accent = AppColors.accent;
  static const Color _cardBg = AppColors.cardBg;
  static const Color _secondaryText = AppColors.secondaryText;

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await LocalHistoryService().getHistory(limit: 200);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
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

  String? _issueTargetSummary(IssueTargetPreset? preset) {
    if (preset == null || !preset.hasReusableTarget) {
      return null;
    }

    if (preset.issueTarget == 'vehicle') {
      return '${tr('LABEL_ISSUE_TARGET')}: ${tr('ISSUE_TO_VEHICLE')} • ${preset.vehiclePlate}';
    }

    if (preset.issueTarget == 'driver') {
      return '${tr('LABEL_ISSUE_TARGET')}: ${tr('ISSUE_TO_DRIVER')} • ${preset.driverName}';
    }

    return null;
  }

  Future<void> _scanNextForPreset(IssueTargetPreset preset) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          initialMovementType: 'out',
          initialIssueTargetPreset: preset,
        ),
      ),
    );
    await _load();
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
          AppScreenHeader(
            title: tr('HISTORY_TITLE'),
            actions: [
              if (_items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: _secondaryText),
                  onPressed: _clearHistory,
                  tooltip: tr('TOOLTIP_CLEAR_HISTORY'),
                ),
            ],
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
      return AppEmptyState(
        icon: Icons.history,
        title: tr('HISTORY_EMPTY_TITLE'),
        subtitle: tr('HISTORY_EMPTY_SUBTITLE'),
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
          final preset = IssueTargetPreset.fromHistoryItem(item);
          final targetSummary = _issueTargetSummary(preset);

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (targetSummary != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                preset!.issueTarget == 'vehicle'
                                    ? Icons.local_shipping
                                    : Icons.person,
                                size: 14,
                                color: _accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  targetSummary,
                                  style: const TextStyle(
                                      color: _secondaryText, fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (preset != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _scanNextForPreset(preset),
                              icon: const Icon(Icons.qr_code_scanner, size: 18),
                              label: Text(tr('BUTTON_SCAN_NEXT')),
                              style: TextButton.styleFrom(
                                foregroundColor: _accent,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
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
