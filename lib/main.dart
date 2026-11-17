import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:permission_handler/permission_handler.dart';
import 'nfc_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.camera.request();
  _cameras = await availableCameras();
  runApp(const DzNfcReaderApp());
}

class DzNfcReaderApp extends StatelessWidget {
  const DzNfcReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'قارئ الهوية NFC',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF38BDF8)),
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer();
  bool _isProcessing = false;
  String _statusMessage = 'وجّه الكاميرا نحو أسطر MRZ في ظهر البطاقة';
  IdCardData? _cardData;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;
    _controller = CameraController(
      _cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
    _startScanningLoop();
  }

  Future<void> _startScanningLoop() async {
    while (mounted && _cardData == null) {
      if (!_isProcessing && _controller != null && _controller!.value.isInitialized) {
        _isProcessing = true;
        try {
          final XFile file = await _controller!.takePicture();
          final inputImage = InputImage.fromFilePath(file.path);
          final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
          File(file.path).deleteSync();

          final mrzResult = _extractMrz(recognizedText.text);
          if (mrzResult != null) {
            await _triggerNfc(
              mrzResult.documentNumber,
              mrzResult.birthDate,
              mrzResult.expiryDate,
            );
          }
        } catch (_) {}
        _isProcessing = false;
      }
      await Future.delayed(const Duration(milliseconds: 700));
    }
  }

  MRZResult? _extractMrz(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.replaceAll(' ', '').toUpperCase())
        .where((l) => l.length >= 28 && l.contains('<'))
        .toList();

    if (lines.length >= 3) {
      try {
        return MRZParser.parse(lines.sublist(lines.length - 3));
      } catch (_) {}
    }
    return null;
  }

  Future<void> _triggerNfc(String docNum, DateTime dob, DateTime expiry) async {
    try {
      final data = await NfcIdService.readBiometricCard(
        documentNumber: docNum,
        birthDate: dob,
        expiryDate: expiry,
        onStatusUpdate: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
      );
      if (mounted) {
        setState(() {
          _cardData = data;
          _statusMessage = 'تمت قراءة الشريحة بنجاح ✅';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'فشلت قراءة NFC، ثبّت البطاقة وأعد المحاولة');
      }
    }
  }

  void _showManualBacDialog() {
    final docCtrl = TextEditingController();
    final dobCtrl = TextEditingController(text: '1995-01-01');
    final expCtrl = TextEditingController(text: '2030-01-01');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال مفتاح NFC يدوياً'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'رقم البطاقة (9 أرقام)')),
            TextField(controller: dobCtrl, decoration: const InputDecoration(labelText: 'تاريخ الميلاد (YYYY-MM-DD)')),
            TextField(controller: expCtrl, decoration: const InputDecoration(labelText: 'تاريخ الانتهاء (YYYY-MM-DD)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _triggerNfc(
                docCtrl.text,
                DateTime.parse(dobCtrl.text),
                DateTime.parse(expCtrl.text),
              );
            },
            child: const Text('بدء قراءة NFC'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قارئ البطاقة البيومترية NFC'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'إدخال يدوي',
            onPressed: _showManualBacDialog,
          ),
          if (_cardData != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _cardData = null;
                  _statusMessage = 'وجّه الكاميرا نحو أسطر MRZ في ظهر البطاقة';
                });
                _startScanningLoop();
              },
            ),
        ],
      ),
      body: _cardData != null ? _buildResultView(_cardData!) : _buildScannerView(),
    );
  }

  Widget _buildScannerView() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _controller != null && _controller!.value.isInitialized
              ? CameraPreview(_controller!)
              : const Center(child: CircularProgressIndicator()),
        ),
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF1E293B),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.nfc, size: 38, color: Color(0xFF38BDF8)),
                const SizedBox(height: 10),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultView(IdCardData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.photoBytes != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      data.photoBytes!,
                      width: 130,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 100),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (data.arabicFullName != null)
                _infoRow('الاسم الكامل (عربي)', data.arabicFullName!),
              _infoRow('اللقب (Nom)', data.lastName),
              _infoRow('الاسم (Prénom)', data.firstName),
              _infoRow('الرقم التعريفي (NIN)', data.nin),
              _infoRow('رقم البطاقة', data.documentNumber),
              _infoRow('تاريخ الميلاد', data.birthDate),
              _infoRow('تاريخ الانتهاء', data.expiryDate),
              _infoRow('الجنس', data.gender),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
