import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../l10n/translations.dart';
import '../services/workshop_api_service.dart';
import 'repair_form_screen.dart';

/// Ekran skanowania tablic rejestracyjnych za pomocą OCR.
/// Po rozpoznaniu tablicy wyszukuje pojazd/naczepę w bazie i otwiera formularz naprawy.
class PlateScannerScreen extends StatefulWidget {
  const PlateScannerScreen({super.key});

  @override
  State<PlateScannerScreen> createState() => _PlateScannerScreenState();
}

class _PlateScannerScreenState extends State<PlateScannerScreen> {
  static const Color _accent = Color(0xFF3498DB);
  static const Color _cardBg = Color(0xFF2C2F3A);
  static const Color _secondaryText = Color(0xFFA0A5B1);

  CameraController? _camera;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _initError;
  bool _cameraReleased = false;
  final _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = tr('ERROR_NO_CAMERAS'));
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _camera = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await _camera!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _initError = tr('ERROR_CAMERA', args: {'error': '$e'}));
    }
  }

  Future<void> _releaseCamera() async {
    if (_cameraReleased) return;
    _cameraReleased = true;
    if (_camera != null && _camera!.value.isInitialized) {
      await _camera!.dispose();
    }
    _camera = null;
  }

  @override
  void dispose() {
    if (!_cameraReleased) _camera?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  /// Regex dla polskich tablic rejestracyjnych (i europejskich).
  static final _plateRegex = RegExp(
    r'^[A-Z]{1,3}\s?[A-Z0-9]{2,5}$',
    caseSensitive: false,
  );

  /// Przytnij zdjęcie do środkowego paska (region tablicy).
  Future<String> _cropToPlateArea(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    final cropW = (imgW * 0.85).round();
    final cropH = (imgW * 0.25).round().clamp(1, imgH.round());
    final cropX = ((imgW - cropW) / 2).round();
    final cropY = ((imgH - cropH) / 2).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(cropX.toDouble(), cropY.toDouble(), cropW.toDouble(), cropH.toDouble()),
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(cropW, cropH.clamp(1, imgH.round()));
    final pngBytes = await cropped.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    cropped.dispose();

    if (pngBytes == null) return imagePath;
    final croppedFile = File('${imagePath}_plate.png');
    await croppedFile.writeAsBytes(pngBytes.buffer.asUint8List());
    return croppedFile.path;
  }

  Future<void> _captureAndRecognize() async {
    if (_isProcessing || _camera == null || !_camera!.value.isInitialized) return;
    setState(() => _isProcessing = true);

    try {
      final xFile = await _camera!.takePicture();
      final croppedPath = await _cropToPlateArea(xFile.path);
      final inputImage = InputImage.fromFilePath(croppedPath);
      final textRecognizer = TextRecognizer();

      try {
        final result = await textRecognizer.processImage(inputImage);
        File(xFile.path).delete().catchError((_) => File(xFile.path));
        if (croppedPath != xFile.path) {
          File(croppedPath).delete().catchError((_) => File(croppedPath));
        }

        if (!mounted) return;

        // Filtruj wyniki szukając czegoś co wygląda jak tablica
        final candidates = <String>[];
        for (final block in result.blocks) {
          for (final line in block.lines) {
            final text = line.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\s]'), '');
            if (text.length >= 5 && text.length <= 10 && _plateRegex.hasMatch(text)) {
              candidates.add(text.replaceAll(' ', ''));
            }
          }
        }

        // Dodaj też surowe linie >= 5 znaków jako fallback
        final allLines = result.blocks
            .expand((b) => b.lines)
            .map((l) => l.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''))
            .where((t) => t.length >= 5 && t.length <= 10)
            .toSet()
            .toList();

        final combined = {...candidates, ...allLines}.toList();

        setState(() => _isProcessing = false);

        if (combined.isEmpty) {
          _showSnack(tr('PLATE_NOT_RECOGNIZED'), Colors.orange);
          return;
        }

        if (combined.length == 1) {
          _searchPlate(combined.first);
        } else {
          _showPlateResults(combined);
        }
      } finally {
        textRecognizer.close();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnack(tr('ERROR_OCR', args: {'error': '$e'}), Colors.red);
      }
    }
  }

  void _showPlateResults(List<String> plates) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Text(tr('PLATE_RESULTS_TITLE'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(tr('PLATE_RESULTS_SUBTITLE'), style: const TextStyle(color: _secondaryText, fontSize: 13)),
            const SizedBox(height: 16),
            ...plates.map((plate) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: const Color(0xFF23262E),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(ctx);
                    _searchPlate(plate);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car, color: _accent, size: 22),
                        const SizedBox(width: 12),
                        Text(plate, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 2)),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios, color: _secondaryText, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  void _searchPlate(String plate) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _cardBg,
        content: Row(
          children: [
            const CircularProgressIndicator(color: _accent),
            const SizedBox(width: 20),
            Text(tr('PLATE_SEARCHING'), style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final result = await WorkshopApiService.searchByPlate(plate);

    if (!mounted) return;
    Navigator.pop(context); // zamknij loading

    if (result['success'] != true) {
      _showSnack(result['error'] ?? tr('ERROR_SEARCH'), Colors.red);
      return;
    }

    if (result['found'] != true || (result['results'] as List).isEmpty) {
      _showNotFoundDialog(plate);
      return;
    }

    final results = List<Map<String, dynamic>>.from(result['results']);
    if (results.length == 1) {
      _openRepairForm(results.first);
    } else {
      _showVehicleSelection(results);
    }
  }

  void _showNotFoundDialog(String plate) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        icon: const Icon(Icons.search_off, color: Colors.orange, size: 48),
        title: Text(tr('PLATE_NOT_FOUND_TITLE'), style: const TextStyle(color: Colors.white)),
        content: Text(
          tr('PLATE_NOT_FOUND_CONTENT', args: {'plate': plate}),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _secondaryText),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showVehicleSelection(List<Map<String, dynamic>> vehicles) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Text(tr('PLATE_VEHICLES_FOUND'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...vehicles.map((v) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: const Color(0xFF23262E),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openRepairForm(v);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          v['object_type'] == 2 ? Icons.rv_hookup : Icons.local_shipping,
                          color: _accent,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v['plate'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                              ),
                              Text(
                                v['object_label'] ?? '',
                                style: const TextStyle(color: _secondaryText, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: _secondaryText, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  void _openRepairForm(Map<String, dynamic> vehicle) async {
    await _releaseCamera();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RepairFormScreen(vehicle: vehicle)),
    );
  }

  void _showManualEntry() {
    _manualController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text(tr('DIALOG_ENTER_PLATE_TITLE'), style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: _manualController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
          decoration: InputDecoration(
            hintText: tr('DIALOG_ENTER_PLATE_HINT'),
            hintStyle: const TextStyle(color: _secondaryText),
            filled: true,
            fillColor: const Color(0xFF23262E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().length >= 4) {
              Navigator.pop(ctx);
              _searchPlate(v.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('BUTTON_CANCEL'), style: const TextStyle(color: _secondaryText)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () {
              final v = _manualController.text.trim();
              if (v.length >= 4) {
                Navigator.pop(ctx);
                _searchPlate(v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
              }
            },
            child: Text(tr('BUTTON_SEARCH')),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _releaseCamera();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(tr('PLATE_SCANNER_TITLE')),
          centerTitle: true,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: tr('TOOLTIP_ENTER_MANUALLY'),
              onPressed: _showManualEntry,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_initError!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _camera == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(tr('CAMERA_STARTING'), style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scanW = constraints.maxWidth * 0.85;
        final scanH = scanW * 0.3;

        return Stack(
          children: [
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _camera!.value.aspectRatio,
                child: CameraPreview(_camera!),
              ),
            ),

            // Overlay with plate-shaped cutout
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _PlateOverlayPainter(scanWidth: scanW, scanHeight: scanH),
            ),

            // Text hint
            Positioned(
              top: (constraints.maxHeight - scanH) / 2 - 40,
              left: 0, right: 0,
              child: Text(
                tr('PLATE_INSTRUCTION'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withAlpha(200)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Manual entry
                    GestureDetector(
                      onTap: _showManualEntry,
                      child: Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.keyboard, color: Colors.white, size: 24),
                      ),
                    ),
                    // Capture button
                    GestureDetector(
                      onTap: _isProcessing ? null : _captureAndRecognize,
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: _isProcessing ? Colors.grey : _accent,
                        ),
                        child: _isProcessing
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                      ),
                    ),
                    // Spacer for symmetry
                    const SizedBox(width: 56),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Rysuje przyciemnione tło z wycięciem w kształcie tablicy rejestracyjnej.
class _PlateOverlayPainter extends CustomPainter {
  final double scanWidth;
  final double scanHeight;

  _PlateOverlayPainter({required this.scanWidth, required this.scanHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: scanWidth, height: scanHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    // Dark overlay
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(140));

    // Border
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF3498DB)
      ..strokeWidth = 2.5);

    // Corners
    const cornerLen = 20.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(rect.left, rect.top + cornerLen), rect.topLeft, paint);
    canvas.drawLine(rect.topLeft, Offset(rect.left + cornerLen, rect.top), paint);
    // Top-right
    canvas.drawLine(Offset(rect.right - cornerLen, rect.top), rect.topRight, paint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + cornerLen), paint);
    // Bottom-left
    canvas.drawLine(Offset(rect.left, rect.bottom - cornerLen), rect.bottomLeft, paint);
    canvas.drawLine(rect.bottomLeft, Offset(rect.left + cornerLen, rect.bottom), paint);
    // Bottom-right
    canvas.drawLine(Offset(rect.right - cornerLen, rect.bottom), rect.bottomRight, paint);
    canvas.drawLine(rect.bottomRight, Offset(rect.right, rect.bottom - cornerLen), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
