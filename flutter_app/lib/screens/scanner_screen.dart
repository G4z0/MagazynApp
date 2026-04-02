import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/code_type.dart';
import '../services/offline_queue_service.dart';
import 'product_form_screen.dart';

/// Główny ekran ze skanerem kodów kreskowych.
///
/// Po zeskanowaniu kodu automatycznie przechodzi
/// do formularza wpisywania nazwy produktu.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late MobileScannerController _controller;

  bool _isProcessing = false;

  // Mnożnik rozmiaru okienka (0.4 - 1.0)
  double _scanSizeFactor = 0.85;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      // Brak filtra formatów — rozpoznaje WSZYSTKIE typy kodów
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    // Zabezpieczenie przed wielokrotnym wykryciem
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _isProcessing = true);

    // Wibracja/dźwięk potwierdzenia
    final scannedValue = barcode.rawValue!;

    // Przejdź do formularza
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductFormScreen(barcode: scannedValue),
      ),
    ).then((_) {
      // Po powrocie z formularza, pozwól skanować ponownie
      setState(() => _isProcessing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skaner kodów'),
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
                  tooltip: '$count w kolejce',
                ),
              );
            },
          ),
          // Przycisk do przełączania lampy błyskowej
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
            tooltip: 'Lampa',
          ),
          // Przycisk do przełączania kamery (przód/tył)
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
            tooltip: 'Przełącz kamerę',
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
              // Podgląd kamery z ograniczonym polem skanowania
              MobileScanner(
                controller: _controller,
                onDetect: _onBarcodeDetected,
                scanWindow: scanWindow,
              ),

              // Nakładka z ramką celownika
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
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              // Slider rozmiaru okienka + instrukcja
              Positioned(
                bottom: 80,
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _isProcessing
                            ? 'Przetwarzanie...'
                            : 'Skieruj kamerę na kod',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
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
                          const Icon(Icons.photo_size_select_small, color: Colors.white70, size: 18),
                          Expanded(
                            child: Slider(
                              value: _scanSizeFactor,
                              min: 0.4,
                              max: 1.0,
                              activeColor: Colors.white,
                              inactiveColor: Colors.white30,
                              onChanged: (v) => setState(() => _scanSizeFactor = v),
                            ),
                          ),
                          const Icon(Icons.photo_size_select_large, color: Colors.white70, size: 18),
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

      // Przycisk do ręcznego wpisania kodu
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showManualEntryDialog(),
        icon: const Icon(Icons.keyboard),
        label: const Text('Wpisz ręcznie'),
      ),
    );
  }

  /// Dialog do ręcznego wpisania kodu
  void _showManualEntryDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wpisz kod'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'np. 5901234123457 lub 2VP340961-111',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.qr_code),
            helperText: 'Kod kreskowy lub kod produktu',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              final code = textController.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(barcode: code),
                  ),
                );
              }
            },
            child: const Text('Dalej'),
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
      'szt': 'szt', 'opak': 'opak', 'l': 'l',
      'kg': 'kg', 'm': 'm', 'kpl': 'kpl',
    };
    return labels[unit] ?? unit;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Uchwyt
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Nagłówek
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_upload, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Kolejka (${_items.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_items.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: _isSyncing ? null : _syncAll,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(_isSyncing ? 'Wysyłanie...' : 'Wyślij'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Lista
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('Kolejka jest pusta',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  controller: widget.scrollController,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final qty = (item['quantity'] as num).toDouble();
                    final qtyStr = qty == qty.roundToDouble()
                        ? qty.toInt().toString()
                        : qty.toString();
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.qr_code, size: 20),
                      ),
                      title: Text(item['product_name'] as String),
                      subtitle: Text(
                        '${item['barcode']}  •  $qtyStr ${_formatUnit(item['unit'] as String)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
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
