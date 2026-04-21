import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../services/auth_service.dart';
import '../services/offline_queue_service.dart';
import 'batch_issue_screen.dart';
import 'manual_product_screen.dart';
import 'scanner_screen.dart';
import 'plate_scanner_screen.dart';
import 'stock_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const Color accent = Color(0xFF3498DB);
  static const Color cardBg = Color(0xFF2C2F3A);
  static const Color darkBg = Color(0xFF1C1E26);
  static const Color secondaryText = Color(0xFFA0A5B1);
  static const Color sidebarBg = Color(0xFF23262E);

  @override
  void initState() {
    super.initState();
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
  }

  void _openPlateScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlateScannerScreen()),
    );
  }

  void _openManualProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManualProductScreen()),
    );
  }

  void _openBatchIssue() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BatchIssueScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDashboard(),
          const StockScreen(),
          const SizedBox(), // placeholder for scanner (opens as push)
          const HistoryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildDashboard() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.warehouse,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tr('HOME_GREETING')} ${AuthService().displayName?.split(' ').first ?? ''}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'LogisticsERP',
                          style: TextStyle(fontSize: 13, color: secondaryText),
                        ),
                      ],
                    ),
                  ),
                  // Offline queue badge
                  ValueListenableBuilder<int>(
                    valueListenable: OfflineQueueService().pendingCount,
                    builder: (context, count, _) {
                      if (count == 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade800,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_upload,
                                size: 16, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('$count',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Tile grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                _DashboardTile(
                  icon: Icons.qr_code_scanner,
                  label: tr('TILE_SCAN_CODE'),
                  onTap: _openScanner,
                ),
                _DashboardTile(
                  icon: Icons.add_box,
                  label: tr('TILE_MANUAL_ADD'),
                  onTap: _openManualProduct,
                ),
                _DashboardTile(
                  icon: Icons.build,
                  label: tr('TILE_ISSUE_FOR_REPAIR'),
                  onTap: _openBatchIssue,
                ),
                _DashboardTile(
                  icon: Icons.rv_hookup,
                  label: tr('TILE_ADD_REPAIR'),
                  onTap: _openPlateScanner,
                ),
                _DashboardTile(
                  icon: Icons.inventory_2,
                  label: tr('TILE_STOCK_LEVELS'),
                  onTap: () => setState(() => _currentIndex = 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1E26),
        border: Border(top: BorderSide(color: Color(0xFF23262E), width: 0.5)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home,
                label: tr('NAV_HOME'),
                isActive: _currentIndex == 0,
                onTap: () => setState(() => _currentIndex = 0),
              ),
              _NavItem(
                icon: Icons.inventory_2,
                label: tr('NAV_STOCK'),
                isActive: _currentIndex == 1,
                onTap: () => setState(() => _currentIndex = 1),
              ),
              // Center scanner button
              GestureDetector(
                onTap: _openScanner,
                child: Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withAlpha(80),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.qr_code_scanner,
                      color: Colors.white, size: 28),
                ),
              ),
              _NavItem(
                icon: Icons.history,
                label: tr('NAV_HISTORY'),
                isActive: _currentIndex == 3,
                onTap: () => setState(() => _currentIndex = 3),
              ),
              _NavItem(
                icon: Icons.more_horiz,
                label: tr('NAV_MORE'),
                isActive: _currentIndex == 4,
                onTap: () => setState(() => _currentIndex = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF3498DB) : const Color(0xFFA0A5B1);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const Color cardBg = Color(0xFF2C2F3A);
  static const Color accent = Color(0xFF3498DB);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 42),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
