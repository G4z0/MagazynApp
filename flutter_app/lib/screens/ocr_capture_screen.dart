import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../l10n/translations.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'product_form_screen.dart';

/// Ekran OCR — podgląd kamery w aplikacji + przycisk migawki.
/// Robi zdjęcie → rozpoznaje tekst → użytkownik wybiera kod produktu.
class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({super.key});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  CameraController? _camera;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _initError;
  bool _cameraReleased = false;
  double _scanSizeFactor = 0.85;

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

      _camera = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _camera!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initError = tr('ERROR_CAMERA', args: {'error': '$e'}));
      }
    }
  }

  /// Zwolnij kamerę synchronicznie (await) przed opuszczeniem ekranu
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
    if (!_cameraReleased) {
      _camera?.dispose();
    }
    super.dispose();
  }

  /// Przycina zdjęcie do obszaru celownika (proporcjonalnie do _scanSizeFactor)
  Future<String> _cropToScanArea(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // Proporcje celownika: szerokość = factor, wysokość = factor * 0.5
    final cropW = (imgW * _scanSizeFactor).round();
    final cropH = (imgW * _scanSizeFactor * 0.5).round().clamp(1, imgH.round());
    final cropX = ((imgW - cropW) / 2).round();
    final cropY = ((imgH - cropH) / 2).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(cropX.toDouble(), cropY.toDouble(), cropW.toDouble(),
          cropH.toDouble()),
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(cropW, cropH.clamp(1, imgH.round()));
    final pngBytes = await cropped.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    cropped.dispose();

    if (pngBytes == null) return imagePath;

    final croppedFile = File('${imagePath}_cropped.png');
    await croppedFile.writeAsBytes(pngBytes.buffer.asUint8List());
    return croppedFile.path;
  }

  Future<void> _captureAndRecognize() async {
    if (_isProcessing || _camera == null || !_camera!.value.isInitialized) {
      return;
    }
    setState(() => _isProcessing = true);

    try {
      final xFile = await _camera!.takePicture();
      final originalPath = xFile.path;

      // Przytnij obraz do obszaru celownika
      final croppedPath = await _cropToScanArea(originalPath);
      final inputImage = InputImage.fromFilePath(croppedPath);
      final textRecognizer = TextRecognizer();

      try {
        final result = await textRecognizer.processImage(inputImage);
        // Usuń tymczasowe pliki
        File(originalPath).delete().catchError((_) => File(originalPath));
        if (croppedPath != originalPath) {
          File(croppedPath).delete().catchError((_) => File(croppedPath));
        }

        if (!mounted) return;

        if (result.text.isEmpty) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('OCR_NO_TEXT')),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        // Zbierz unikalne linie tekstu (min 3 znaki)
        final lines = result.blocks
            .expand((block) => block.lines)
            .map((line) => line.text.trim())
            .where((text) => text.length >= 3)
            .toSet()
            .toList();

        if (!mounted) return;
        setState(() => _isProcessing = false);

        if (lines.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('OCR_NO_CODES')),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        _showTextResults(lines);
      } finally {
        textRecognizer.close();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('ERROR_OCR', args: {'error': '$e'})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showTextResults(List<String> lines) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _OcrResultsSheet(
        lines: lines,
        onSelect: (code) async {
          final sheetNavigator = Navigator.of(ctx);
          final rootNavigator = Navigator.of(context);
          await _releaseCamera();
          if (!mounted) return;
          sheetNavigator.pop();
          rootNavigator.pushReplacement(
            MaterialPageRoute(
              builder: (_) => ProductFormScreen(barcode: code),
            ),
          );
        },
      ),
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
          title: Text(tr('OCR_TITLE')),
          centerTitle: true,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
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
              Text(
                _initError!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
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
            Text(
              tr('CAMERA_STARTING'),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaWidth = constraints.maxWidth * _scanSizeFactor;
        final scanAreaHeight = scanAreaWidth * 0.5;

        return Stack(
          children: [
            // Podgląd kamery
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _camera!.value.aspectRatio,
                child: CameraPreview(_camera!),
              ),
            ),

            // Nakładka z ramką celownika
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OcrOverlayPainter(
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

            // Wskazówka na górze
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  tr('OCR_INSTRUCTION'),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // Slider rozmiaru okienka
            Positioned(
              bottom: 140,
              left: 16,
              right: 16,
              child: Container(
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
                        onChanged: (v) => setState(() => _scanSizeFactor = v),
                      ),
                    ),
                    const Icon(Icons.photo_size_select_large,
                        color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),

            // Przycisk migawki + spinner
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _isProcessing ? null : _captureAndRecognize,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isProcessing ? Colors.grey : AppColors.accent,
                    ),
                    child: _isProcessing
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 36,
                          ),
                  ),
                ),
              ),
            ),

            // Etykieta pod przyciskiem
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _isProcessing ? tr('OCR_PROCESSING') : tr('OCR_TAKE_PHOTO'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Nakładka przyciemniona z otworem
class _OcrOverlayPainter extends CustomPainter {
  final double scanWidth;
  final double scanHeight;
  final double borderRadius;

  _OcrOverlayPainter({
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

/// Bottom sheet z edytowalnymi wynikami OCR
class _OcrResultsSheet extends StatefulWidget {
  final List<String> lines;
  final Future<void> Function(String code) onSelect;

  const _OcrResultsSheet({required this.lines, required this.onSelect});

  @override
  State<_OcrResultsSheet> createState() => _OcrResultsSheetState();
}

class _OcrResultsSheetState extends State<_OcrResultsSheet> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers =
        widget.lines.map((l) => TextEditingController(text: l)).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const AppModalHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.text_fields, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  tr('OCR_RESULTS_TITLE',
                      args: {'count': '${_controllers.length}'}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              tr('OCR_EDIT_INSTRUCTION'),
              style:
                  const TextStyle(color: AppColors.secondaryText, fontSize: 13),
            ),
          ),
          Divider(height: 16, color: Colors.white.withAlpha(20)),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: _controllers.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.white.withAlpha(20)),
              itemBuilder: (context, index) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      // Numer
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.accent.withAlpha(35),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Edytowalne pole
                      Expanded(
                        child: TextField(
                          controller: _controllers[index],
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: appInputDecoration(
                            label: tr('OCR_USE_CODE'),
                            dense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Przycisk wyboru
                      IconButton(
                        icon: const Icon(Icons.check_circle,
                            color: AppColors.success, size: 28),
                        tooltip: tr('OCR_USE_CODE'),
                        onPressed: () {
                          final code = _controllers[index].text.trim();
                          if (code.isNotEmpty) {
                            widget.onSelect(code);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
