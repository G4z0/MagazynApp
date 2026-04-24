import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/translations.dart';
import '../models/issue_target_preset.dart';
import '../services/offline_queue_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'ocr_capture_screen.dart';
import 'product_form_screen.dart';

/// Główny ekran ze skanerem kodów kreskowych.
///
/// Po zeskanowaniu kodu automatycznie przechodzi
/// do formularza wpisywania nazwy produktu.
///
/// Jeśli [returnBarcodeOnly] = true, po potwierdzeniu kodu
/// wraca z wynikiem (String) zamiast przechodzić do formularza.
class ScannerScreen extends StatefulWidget {
  final bool returnBarcodeOnly;
  final String initialMovementType;
  final IssueTargetPreset? initialIssueTargetPreset;

  const ScannerScreen({
    super.key,
    this.returnBarcodeOnly = false,
    this.initialMovementType = 'in',
    this.initialIssueTargetPreset,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  static const Color _cardBg = AppColors.cardBg;
  static const Color _inputBg = AppColors.inputBg;
  static const Color _accent = AppColors.accent;
  MobileScannerController? _controller;

  // Wykryty kod — czeka na potwierdzenie użytkownika
  String? _detectedCode;
  String? _detectedFormat;
  bool _isNavigating = false;

  // Mnożnik rozmiaru okienka wizualnego (0.4 - 1.0)
  double _scanSizeFactor = 0.85;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  void _startCamera() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isNavigating) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final value = barcode.rawValue!;
    final format = barcode.format.name;

    // Pokaż wykryty kod — czekaj na potwierdzenie
    if (_detectedCode != value) {
      setState(() {
        _detectedCode = value;
        _detectedFormat = format;
      });
    }
  }

  void _confirmCode() {
    if (_detectedCode == null || _isNavigating) return;
    setState(() => _isNavigating = true);

    final code = _detectedCode!;

    // W trybie zwracania kodu — wróć z wynikiem
    if (widget.returnBarcodeOnly) {
      Navigator.pop(context, code);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductFormScreen(
          barcode: code,
          initialMovementType: widget.initialMovementType,
          initialIssueTargetPreset: widget.initialIssueTargetPreset,
        ),
      ),
    ).then((_) {
      setState(() {
        _detectedCode = null;
        _detectedFormat = null;
        _isNavigating = false;
      });
    });
  }

  void _rejectCode() {
    setState(() {
      _detectedCode = null;
      _detectedFormat = null;
    });
  }

  /// Otwórz ekran OCR (rozpoznawanie tekstu)
  void _openOcrScreen() {
    // Usuń kamerę całkowicie
    _controller?.dispose();
    _controller = null;
    setState(() {});

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OcrCaptureScreen()),
    ).then((_) {
      if (!mounted) return;
      // OCR zwalnia kamerę przed pop, ale dajmy chwilę na zwolnienie zasobu HW
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _startCamera();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('SCANNER_TITLE')),
        centerTitle: true,
        actions: [
          // Wskaźnik kolejki offline
          ValueListenableBuilder<int>(
            valueListenable: OfflineQueueService().pendingCount,
            builder: (context, count, _) {
              if (count == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: Badge(
                    label: Text('$count'),
                    child: const Icon(Icons.cloud_upload),
                  ),
                  onPressed: () => _showQueueSheet(),
                  tooltip:
                      tr('SCANNER_QUEUE_TOOLTIP', args: {'count': '$count'}),
                ),
              );
            },
          ),
          // Przycisk do przełączania lampy błyskowej
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
            tooltip: tr('SCANNER_TORCH_TOOLTIP'),
          ),
          // Przycisk do przełączania kamery (przód/tył)
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller?.switchCamera(),
            tooltip: tr('SCANNER_SWITCH_CAMERA'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scanAreaWidth = constraints.maxWidth * _scanSizeFactor;
          final scanAreaHeight = scanAreaWidth * 0.5;
          final scanWindow = Rect.fromCenter(
            center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
            width: scanAreaWidth,
            height: scanAreaHeight,
          );

          return Stack(
            children: [
              // Podgląd kamery z ograniczonym polem detekcji
              if (_controller != null)
                MobileScanner(
                  key: ValueKey(_controller.hashCode),
                  controller: _controller!,
                  onDetect: _onBarcodeDetected,
                  scanWindow: scanWindow,
                ),

              // Nakładka z ramką celownika (tylko wizualnie)
              CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _ScanOverlayPainter(
                  scanWidth: scanAreaWidth,
                  scanHeight: scanAreaHeight,
                  borderRadius: 12,
                ),
              ),
              Center(
                child: Container(
                  width: scanAreaWidth,
                  height: scanAreaHeight,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _detectedCode != null
                          ? Colors.greenAccent
                          : Colors.white,
                      width: _detectedCode != null ? 3 : 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              // Panel potwierdzenia wykrytego kodu
              if (_detectedCode != null)
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: Card(
                    color: _cardBg,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.qr_code_scanner,
                                  color: AppColors.success, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr('SCANNER_CODE_DETECTED'),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.secondaryText)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _detectedCode!,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        letterSpacing: 1.2,
                                        color: Colors.white,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_detectedFormat != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Chip(
                                  label: Text(_detectedFormat!,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white)),
                                  backgroundColor: _inputBg,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _rejectCode,
                                  icon: const Icon(Icons.close),
                                  label: Text(tr('BUTTON_REJECT')),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: _confirmCode,
                                  icon: const Icon(Icons.check),
                                  label: Text(tr('BUTTON_CONFIRM'),
                                      style: const TextStyle(fontSize: 16)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Slider rozmiaru okienka + instrukcja (ukryte gdy kod wykryty)
              if (_detectedCode == null)
                Positioned(
                  bottom: 80,
                  left: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          tr('SCANNER_INSTRUCTION'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_size_select_small,
                                color: Colors.white70, size: 18),
                            Expanded(
                              child: Slider(
                                value: _scanSizeFactor,
                                min: 0.4,
                                max: 1.0,
                                activeColor: Colors.white,
                                inactiveColor: Colors.white30,
                                onChanged: (v) =>
                                    setState(() => _scanSizeFactor = v),
                              ),
                            ),
                            const Icon(Icons.photo_size_select_large,
                                color: Colors.white70, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),

      // Przyciski dolne — ukryte gdy widoczna karta potwierdzenia
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _detectedCode != null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FloatingActionButton.extended(
                        heroTag: 'ocr',
                        onPressed: _openOcrScreen,
                        icon: const Icon(Icons.document_scanner, size: 20),
                        label: const Text('OCR'),
                        backgroundColor: _accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FloatingActionButton.extended(
                        heroTag: 'manual',
                        onPressed: () => _showManualEntryDialog(),
                        icon: const Icon(Icons.keyboard, size: 20),
                        label: Text(tr('BUTTON_MANUAL')),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Dialog do ręcznego wpisania kodu
  void _showManualEntryDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text(tr('DIALOG_ENTER_CODE_TITLE'),
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: tr('DIALOG_ENTER_CODE_HINT'),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: _inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(Icons.qr_code, color: _accent),
            helperText: tr('DIALOG_ENTER_CODE_HELPER'),
            helperStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('BUTTON_CANCEL'),
                style: const TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () {
              final code = textController.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                if (widget.returnBarcodeOnly) {
                  Navigator.pop(context, code);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(
                        barcode: code,
                        initialMovementType: widget.initialMovementType,
                        initialIssueTargetPreset:
                            widget.initialIssueTargetPreset,
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(tr('BUTTON_NEXT')),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet z listą zakolejkowanych produktów
  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => _QueueListSheet(
          scrollController: scrollController,
        ),
      ),
    );
  }
}

/// Widget listy kolejki offline
class _QueueListSheet extends StatefulWidget {
  final ScrollController scrollController;
  const _QueueListSheet({required this.scrollController});

  @override
  State<_QueueListSheet> createState() => _QueueListSheetState();
}

class _QueueListSheetState extends State<_QueueListSheet> {
  static const Color _accent = Color(0xFF3498DB);
  static const Color _secondaryText = Color(0xFFA0A5B1);

  List<Map<String, dynamic>> _items = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await OfflineQueueService().getAll();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncing = true);
    await OfflineQueueService().syncQueue();
    await _loadItems();
    if (mounted) setState(() => _isSyncing = false);
  }

  Future<void> _removeItem(int id) async {
    await OfflineQueueService().removeItem(id);
    await _loadItems();
  }

  String _formatUnit(String unit) {
    const labels = {
      'szt': 'szt',
      'opak': 'opak',
      'l': 'l',
      'kg': 'kg',
      'm': 'm',
      'kpl': 'kpl',
    };
    return labels[unit] ?? unit;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppModalHandle(),
        // Nagłówek
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_upload, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('QUEUE_HEADER', args: {'count': '${_items.length}'}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_items.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: _isSyncing ? null : _syncAll,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _accent),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(
                      _isSyncing ? tr('BUTTON_SENDING') : tr('BUTTON_SEND')),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withAlpha(20)),
        // Lista
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text(tr('QUEUE_EMPTY'),
                      style: const TextStyle(color: _secondaryText)),
                )
              : ListView.separated(
                  controller: widget.scrollController,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.white.withAlpha(20)),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final qty = (item['quantity'] as num).toDouble();
                    final qtyStr = qty == qty.roundToDouble()
                        ? qty.toInt().toString()
                        : qty.toString();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _accent.withAlpha(40),
                        child:
                            const Icon(Icons.qr_code, size: 20, color: _accent),
                      ),
                      title: Text(item['product_name'] as String,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${item['barcode']}  •  $qtyStr ${_formatUnit(item['unit'] as String)}',
                        style: const TextStyle(
                            color: _secondaryText, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade300),
                        onPressed: () => _removeItem(item['id'] as int),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Rysuje przyciemnioną nakładkę z przezroczystym otworem na skaner
class _ScanOverlayPainter extends CustomPainter {
  final double scanWidth;
  final double scanHeight;
  final double borderRadius;

  _ScanOverlayPainter({
    required this.scanWidth,
    required this.scanHeight,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final center = Offset(size.width / 2, size.height / 2);
    final scanRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: scanWidth, height: scanHeight),
      Radius.circular(borderRadius),
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(scanRect);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
