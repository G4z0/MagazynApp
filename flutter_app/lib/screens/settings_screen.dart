import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../l10n/translations.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/local_history_service.dart';
import '../services/offline_queue_service.dart';
import 'login_screen.dart';

/// Ekran ustawień / "Więcej"
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const Color cardBg = Color(0xFF2C2F3A);
  static const Color accent = Color(0xFF3498DB);
  static const Color _secondaryText = Color(0xFFA0A5B1);
  static const String _serverHost = '192.168.1.42';

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.warehouse, color: Colors.white, size: 28),
        ),
        title: Text(tr('SETTINGS_ABOUT_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('SETTINGS_VERSION'),
                style: const TextStyle(color: _secondaryText, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              tr('SETTINGS_ABOUT_DESCRIPTION'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _secondaryText, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              tr('SETTINGS_ABOUT_FEATURES'),
              style: const TextStyle(color: _secondaryText, fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _checkServer(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        content: Row(
          children: [
            const CircularProgressIndicator(color: accent),
            const SizedBox(width: 20),
            Text(tr('SETTINGS_CHECKING_CONNECTION'),
                style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    String status;
    IconData icon;
    Color iconColor;
    String details;

    try {
      final response = await http
          .get(Uri.parse(
              'http://$_serverHost/barcode_api/barcode.php?barcode=_ping'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 400) {
        status = tr('STATUS_CONNECTED');
        icon = Icons.check_circle;
        iconColor = Colors.green;
        details = tr('STATUS_CONNECTED_DETAIL', args: {'host': _serverHost});
      } else {
        status = tr('STATUS_SERVER_ERROR');
        icon = Icons.warning;
        iconColor = Colors.orange;
        details = tr('STATUS_SERVER_ERROR_DETAIL',
            args: {'code': '${response.statusCode}'});
      }
    } catch (e) {
      status = tr('STATUS_NO_CONNECTION');
      icon = Icons.cancel;
      iconColor = Colors.red;
      details = tr('STATUS_NO_CONNECTION_DETAIL', args: {'host': _serverHost});
    }

    if (!context.mounted) return;
    Navigator.pop(context); // zamknij loading

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        icon: Icon(icon, color: iconColor, size: 48),
        title: Text(status, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(details,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _secondaryText, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dns, color: _secondaryText, size: 18),
                  const SizedBox(width: 8),
                  Text('http://$_serverHost',
                      style: const TextStyle(
                          color: _secondaryText,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showOfflineQueue(BuildContext context) async {
    final items = await OfflineQueueService().getAll();
    final count = items.length;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Row(
              children: [
                const Icon(Icons.cloud_upload, color: accent, size: 24),
                const SizedBox(width: 10),
                Text(tr('SETTINGS_OFFLINE_QUEUE'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: count > 0
                        ? Colors.orange.withAlpha(40)
                        : Colors.green.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: count > 0 ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (count == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_done,
                          color: Colors.green, size: 40),
                      const SizedBox(height: 8),
                      Text(tr('QUEUE_ALL_SYNCED'),
                          style: const TextStyle(
                              color: _secondaryText, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(tr('QUEUE_NO_PENDING'),
                          style: const TextStyle(
                              color: _secondaryText, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                tr('QUEUE_PENDING_INFO'),
                style: const TextStyle(color: _secondaryText, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final type = item['movement_type'] == 'in'
                        ? tr('LOG_STOCK_IN')
                        : tr('LOG_STOCK_OUT');
                    final icon = item['movement_type'] == 'in'
                        ? Icons.add_circle
                        : Icons.remove_circle;
                    final color = item['movement_type'] == 'in'
                        ? Colors.green
                        : Colors.orange;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$type: ${item['product_name'] ?? '?'}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${item['quantity']} ${item['unit']} — ${item['barcode']}',
                                  style: const TextStyle(
                                      color: _secondaryText, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () {
                    Navigator.pop(ctx);
                    OfflineQueueService().syncQueue();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(tr('QUEUE_SYNC_ATTEMPT')),
                          duration: const Duration(seconds: 2)),
                    );
                  },
                  icon: const Icon(Icons.sync, color: Colors.white),
                  label: Text(tr('BUTTON_FORCE_SYNC')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Row(
              children: [
                const Icon(Icons.translate, color: accent, size: 24),
                const SizedBox(width: 10),
                Text(tr('SETTINGS_LANGUAGE'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            ...availableLanguages.map((lang) {
              final isSelected = lang['code'] == currentLang;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected
                      ? accent.withAlpha(30)
                      : const Color(0xFF23262E),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (lang['code'] != currentLang) {
                        await setLanguage(lang['code']!);
                        if (context.mounted) {
                          MagazynApp.restartApp(context);
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Text(lang['flag']!,
                              style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 14),
                          Text(lang['name']!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500)),
                          const Spacer(),
                          if (isSelected)
                            const Icon(Icons.check_circle,
                                color: accent, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Text(tr('DIALOG_LOGOUT_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: Text(tr('DIALOG_LOGOUT_CONTENT'),
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
            child: Text(tr('BUTTON_LOGOUT')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await LocalHistoryService().add(
        actionType: 'logout',
        title: tr('LOG_LOGOUT'),
        subtitle: AuthService().displayName,
        userName: AuthService().displayName,
      );
      await AuthService().logout();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              tr('SETTINGS_TITLE'),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
          // Karta użytkownika
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: accent.withAlpha(40),
                  child: Text(
                    (auth.displayName ?? '?').substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: accent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.displayName ?? tr('USER_FALLBACK_NAME'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        auth.email ?? '',
                        style: const TextStyle(
                            color: _secondaryText, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            label: tr('SETTINGS_ABOUT'),
            subtitle: tr('SETTINGS_ABOUT_SUBTITLE'),
            onTap: () => _showAbout(context),
          ),
          _SettingsTile(
            icon: Icons.wifi,
            label: tr('SETTINGS_API_SERVER'),
            subtitle: _serverHost,
            onTap: () => _checkServer(context),
          ),
          _SettingsTile(
            icon: Icons.cloud_upload,
            label: tr('SETTINGS_OFFLINE_QUEUE_TILE'),
            subtitle: tr('SETTINGS_OFFLINE_QUEUE_SUBTITLE'),
            onTap: () => _showOfflineQueue(context),
          ),
          _SettingsTile(
            icon: Icons.translate,
            label: tr('SETTINGS_LANGUAGE'),
            subtitle: availableLanguages.firstWhere(
                (l) => l['code'] == currentLang,
                orElse: () => availableLanguages.first)['name']!,
            onTap: () => _showLanguagePicker(context),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.logout,
            label: tr('SETTINGS_LOGOUT'),
            subtitle: tr('SETTINGS_LOGOUT_SUBTITLE'),
            onTap: () => _logout(context),
            iconColor: Colors.red,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: SettingsScreen.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(icon, color: iconColor ?? SettingsScreen.accent, size: 22),
        ),
        title: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}
