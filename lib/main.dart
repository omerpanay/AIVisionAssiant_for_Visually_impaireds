import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart ';
import 'dart:convert';
import 'dart:async';
import 'services/vision_service.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  // Kamera izinlerini kontrol et ve kameraları al
  try {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw 'Kamera bulunamadı';
    }
    runApp(MyApp(camera: cameras.first));
  } catch (e) {
    print('Kamera başlatma hatası: $e');
    // Hata durumunda kullanıcıya bilgi ver
  }
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Vision Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: VisionAssistantPage(
        title: 'AI Vision Assistant',
        camera: camera,
      ),
    );
  }
}

class VisionAssistantPage extends StatefulWidget {
  final CameraDescription camera;

  const VisionAssistantPage({
    super.key,
    required this.title,
    required this.camera,
  });

  final String title;

  @override
  State<VisionAssistantPage> createState() => _VisionAssistantPageState();
}

class _VisionAssistantPageState extends State<VisionAssistantPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final VisionService _visionService = VisionService();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  String _lastDescription = 'Çevrenizi tanımlamak için butona basılı tutun';
  Timer? _analysisTimer;

  @override
  void initState() {
    super.initState();
    // Kamera kontrolcüsünü başlat
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    // Future'ı başlat
    _initializeControllerFuture = _initCamera();
    _initializeTts();
  }

  Future<void> _initCamera() async {
    try {
      // Kamera izinlerini kontrol et
      final status = await ph.Permission.camera.request();
      if (!status.isGranted) {
        throw Exception('Kamera izni reddedildi');
      }

      // Kamerayı başlat
      await _controller.initialize();
      if (mounted) {
        setState(() {});
      }
      await _controller.lockCaptureOrientation();
    } catch (e) {
      print('Kamera başlatma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kamera başlatılamadı: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      rethrow; // Hatayı yukarı fırlat
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _flutterTts.stop();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeTts() async {
    try {
      await _flutterTts.setLanguage('tr-TR');
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.8);
      await _flutterTts.setVolume(1.0);

      // TTS durumunu kontrol et
      var available = await _flutterTts.isLanguageAvailable('tr-TR');
      if (!available) {
        print('Türkçe dil paketi bulunamadı, varsayılan dil kullanılacak');
        await _flutterTts.setLanguage('en-US');
      }

      // Test amaçlı bir mesaj söyle
      await _speakDescription('Sistem hazır');
    } catch (e) {
      print('TTS başlatma hatası: $e');
    }
  }

  Future<void> _speakDescription(String text) async {
    try {
      // Önceki konuşma devam ediyorsa durdur
      await _flutterTts.stop();

      // Biraz bekle
      await Future.delayed(const Duration(milliseconds: 500));

      // Yeni metni oku
      var result = await _flutterTts.speak(text);
      if (result != 1) {
        print('Konuşma hatası: $result');
      }
    } catch (e) {
      print('Konuşma hatası: $e');
    }
  }

  Future<void> _analyzeImage() async {
    print("Görüntü analizi başlatılıyor..."); // Debug için
    if (!_controller.value.isInitialized) {
      print('Kamera henüz başlatılmadı');
      return;
    }

    try {
      await _flutterTts.stop();

      final image = await _controller.takePicture();
      print("Fotoğraf çekildi"); // Debug için

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      print("Görüntü base64'e dönüştürüldü"); // Debug için

      setState(() {
        _lastDescription = 'Görüntü analiz ediliyor...';
      });

      final description = await _visionService.getImageDescription(base64Image);
      print("API'den yanıt alındı: $description"); // Debug için

      if (!mounted) return;

      setState(() {
        _lastDescription = description;
      });

      await _speakDescription(description);
    } catch (e) {
      print("Hata oluştu: $e"); // Debug için
      final errorMessage = 'Görüntü analiz edilirken bir hata oluştu: $e';
      if (!mounted) return;

      setState(() {
        _lastDescription = errorMessage;
      });
      await _speakDescription('Bir hata oluştu');
    }
  }

  Future<void> _toggleListening() async {
    print("Toggle Listening çağrıldı. Şu anki durum: $_isListening");

    if (!_controller.value.isInitialized) {
      print('Kamera henüz başlatılmadı');
      return;
    }

    setState(() {
      _isListening = !_isListening;
    });

    if (_isListening) {
      print("Analiz başlatılıyor...");
      _lastDescription = 'Çevre analiz ediliyor...';
      await _speakDescription('Analiz başlatılıyor');

      // İlk analizi başlat
      if (_isListening) {
        _analyzeImage();
      }

      // Periyodik analizi başlat
      _analysisTimer?.cancel();
      _analysisTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
        if (_isListening) {
          _analyzeImage();
        }
      });
    } else {
      print("Analiz durduruluyor...");
      _analysisTimer?.cancel();
      await _flutterTts.stop();
      await _speakDescription('Analiz durduruldu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primaryContainer,
        title: Text(
          widget.title,
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              _showHelpDialog(context);
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Card(
                margin: const EdgeInsets.all(16.0),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FutureBuilder<void>(
                    future: _initializeControllerFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done) {
                        return CameraPreview(_controller);
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: colorScheme.error,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Kamera hatası: ${snapshot.error}',
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ],
                          ),
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Card(
                margin: const EdgeInsets.all(16.0),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        _lastDescription,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isListening ? Icons.lens : Icons.lens_outlined,
                              size: 12,
                              color: _isListening
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isListening
                                  ? 'Analiz ediliyor...'
                                  : 'Analiz edilmiyor',
                              style: TextStyle(
                                color: _isListening
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: GestureDetector(
        onLongPressStart: (_) {
          print("Basılı tutma başladı"); // Debug için
          _toggleListening();
        },
        onLongPressEnd: (_) {
          print("Basılı tutma bitti"); // Debug için
          if (_isListening) {
            _toggleListening();
          }
        },
        child: FloatingActionButton.large(
          onPressed: null, // Tek tıklamayı devre dışı bırak
          tooltip: 'Çevreyi tanımlamak için basılı tutun',
          backgroundColor:
              _isListening ? colorScheme.primaryContainer : colorScheme.primary,
          child: Icon(
            _isListening ? Icons.camera : Icons.camera_alt,
            color: _isListening ? colorScheme.primary : colorScheme.onPrimary,
            size: 32,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Nasıl Kullanılır?'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('1. Kamera önizlemesi üst bölümde gösterilir.'),
                SizedBox(height: 8),
                Text(
                    '2. Çevrenizi analiz ettirmek için alttaki kamera butonuna basılı tutun.'),
                SizedBox(height: 8),
                Text(
                    '3. Analiz sonuçları sesli olarak okunacak ve ekranda gösterilecektir.'),
                SizedBox(height: 8),
                Text('4. Analizi durdurmak için butonu bırakın.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Anladım'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
