import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/websocket_service.dart';
import '../services/event_bus.dart';
// Conditional import: web gets dart:html-based helper; native gets no-op stub.
import '../utils/web_video_helper_stub.dart'
    if (dart.library.html) '../utils/web_video_helper.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  // Camera/Image State
  File? _selectedImage;
  File? _selectedVideo;
  VideoPlayerController? _videoPlayerController;
  String? _webVideoBlobUrl; // blob URL for web video preview
  // XFile references kept for web-safe filename access
  XFile? _selectedImageXFile;
  XFile? _selectedVideoXFile;
  bool _cameraReady = false;
  bool _cameraStarted = false;

  // Detection State
  bool _loading = false;
  bool _isAutoMonitoring = false;
  bool _isMonitoringActive = false;
  Timer? _autoMonitorTimer;
  Uint8List? _selectedVideoBytes;
  Uint8List? _selectedImageBytes;
  List<dynamic>? _frameResults;

  // Antigravity Context State
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _latController =
      TextEditingController(text: "33.6844");
  final TextEditingController _lonController =
      TextEditingController(text: "73.0479");
  bool _testMode = false;

  // Results
  bool _detected = false;
  String _crisisType = 'None';
  double _confidence = 0.0;
  String _severity = 'none';
  String _recommendation = 'none';

  // Antigravity Results State
  String? _currentCrisisId;
  Map<String, dynamic>? _allocationPlan;
  Map<String, dynamic>? _simulation;
  List<dynamic>? _notifications;

  Map<String, dynamic>? _weatherData;
  bool _loadingWeather = false;
  Timer? _weatherTimer;

  final WebSocketService _wsService = WebSocketService();
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
    _weatherTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchWeather());
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      bool isOnline = false;
      if (result is List) {
        isOnline = !(result as List).contains(ConnectivityResult.none);
      } else {
        isOnline = result != ConnectivityResult.none;
      }
    });
    _wsService.connect((data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚨 Broadcast: ${data['crisis_type']} detected!'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() {
          if (data.containsKey('detected')) _detected = data['detected'];
          if (data.containsKey('crisis_type')) _crisisType = data['crisis_type'].toString().toUpperCase();
          if (data.containsKey('confidence')) _confidence = (data['confidence'] as num).toDouble();
          if (data.containsKey('severity')) _severity = data['severity'];
          if (data.containsKey('crisis_id')) _currentCrisisId = data['crisis_id'];
          if (data.containsKey('allocation_plan')) _allocationPlan = data['allocation_plan'];
          if (data.containsKey('simulation')) _simulation = data['simulation'];
          if (data.containsKey('notifications')) _notifications = data['notifications'];
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Camera helpers
  // ---------------------------------------------------------------------------

  /// Captures a photo from the camera.
  /// On Web, [ImageSource.camera] triggers the browser's file-picker
  /// (no direct webcam stream via image_picker on web). We read the
  /// bytes via [XFile.readAsBytes()] so it works on both web and mobile.
  Future<void> _initCamera() async {
    try {
      final picker = ImagePicker();
      // On web, ImageSource.camera opens a file picker filtered to images
      // (the browser may or may not offer a webcam capture option)
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (photo != null) {
        // Use XFile.readAsBytes() – works on both web and mobile
        final bytes = await photo.readAsBytes();
        if (mounted) {
          setState(() {
            _isMonitoringActive = true;
            _selectedImageXFile = photo;
            // File(path) is only valid on non-web platforms
            _selectedImage = kIsWeb ? null : File(photo.path);
            _selectedImageBytes = bytes;
            _selectedVideoXFile = null;
            _selectedVideo = null;
            _selectedVideoBytes = null;
            _videoPlayerController?.pause();
            _videoPlayerController?.dispose();
            _videoPlayerController = null;
            _cameraReady = true;
          });
        }
        await _detectCrisisCloud();
        if (mounted) {
          setState(() {
            _isMonitoringActive = _isAutoMonitoring;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cameraStarted = false;
            _cameraReady = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) {
        setState(() {
          _cameraStarted = false;
          _cameraReady = false;
        });
      }
    }
  }

  Future<void> _startCamera() async {
    setState(() {
      _cameraStarted = true;
    });
    await _initCamera();
  }

  // ---------------------------------------------------------------------------
  // Auto-monitoring
  // ---------------------------------------------------------------------------

  void _toggleAutoMonitoring() {
    setState(() {
      _isAutoMonitoring = !_isAutoMonitoring;
      _isMonitoringActive = _isAutoMonitoring;
    });

    if (_isAutoMonitoring) {
      // Cloud-only periodic detection every 15 s
      _autoMonitorTimer =
          Timer.periodic(const Duration(seconds: 15), (timer) {
        if (!_loading) _captureAndDetect();
      });
    } else {
      _autoMonitorTimer?.cancel();
    }
  }

  Future<void> _captureAndDetect() async {
    if (_selectedImageBytes == null && _selectedVideoBytes == null) return;
    await _detectCrisisCloud();
  }

  // ---------------------------------------------------------------------------
  // Video picker
  // ---------------------------------------------------------------------------

  /// Picks a video from the gallery/file system and immediately
  /// triggers crisis detection. Uses [XFile.readAsBytes()] for
  /// web-safe byte access (File(path) does not work on Flutter Web).
  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final XFile? video =
          await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        // Read bytes via XFile – works on web and mobile
        final bytes = await video.readAsBytes();

        // Initialize video player
        _videoPlayerController?.pause();
        _videoPlayerController?.dispose();
        _videoPlayerController = null;

        // Revoke previous blob URL to free memory
        if (_webVideoBlobUrl != null) {
          WebVideoHelper.revokeBlobUrl(_webVideoBlobUrl!);
        }
        String? blobUrl;

        if (kIsWeb) {
          // Create a blob URL — video_player_web can play blob: URLs
          blobUrl = WebVideoHelper.createBlobUrl(bytes, 'video/mp4');
          try {
            _videoPlayerController =
                VideoPlayerController.networkUrl(Uri.parse(blobUrl));
            await _videoPlayerController!.initialize();
            _videoPlayerController!.setLooping(true);
            _videoPlayerController!.play();
          } catch (e) {
            debugPrint('VideoPlayer (web) initialization failed: $e');
            // Fallback: keep blobUrl for HtmlElementView fallback
          }
        } else {
          _videoPlayerController =
              VideoPlayerController.file(File(video.path));
          try {
            await _videoPlayerController!.initialize();
            _videoPlayerController!.setLooping(true);
            _videoPlayerController!.play();
          } catch (e) {
            debugPrint('VideoPlayer initialization failed: $e');
          }
        }

        setState(() {
          _isMonitoringActive = true;
          _selectedVideoXFile = video;
          _selectedVideo = kIsWeb ? null : File(video.path);
          _selectedVideoBytes = bytes;
          _selectedImageXFile = null;
          _selectedImage = null;
          _selectedImageBytes = null;
          _cameraReady = true;
          _cameraStarted = true;
          _webVideoBlobUrl = blobUrl;
        });
        // Auto-trigger detection immediately after picking
        await _detectCrisisCloud();
        if (mounted) {
          setState(() {
            _isMonitoringActive = _isAutoMonitoring;
          });
        }
      }
    } catch (e) {
      debugPrint('Video picking failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick video: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud detection (only mode)
  // ---------------------------------------------------------------------------

  /// Returns true when device has internet access.
  Future<bool> _checkOnline() async {
    final result = await Connectivity().checkConnectivity();
    if (result is List) {
      // connectivity_plus ≥ 5 may return a List<ConnectivityResult>
      return !(result as List).contains(ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }



  Future<void> _detectCrisisCloud() async {
    // Guard: need at least one media source
    if (_selectedVideoBytes == null && _selectedImageBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error: No image or video selected.'),
              backgroundColor: AppColors.error),
        );
      }
      return;
    }

    if (!_isMonitoringActive) return;

    // Online check
    final bool isOnline = await _checkOnline();
    if (!isOnline) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Cloud detection requires internet.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _fetchWeather();
    setState(() {
      _loading = true;
      _allocationPlan = null;
      _frameResults = null;
    });

    try {
      // Choose endpoint; fall back to /detect if detectVideo is empty
      String apiUrl;
      if (_selectedVideoBytes != null) {
        if (ApiConfig.detectVideo.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Warning: detectVideo endpoint not configured, falling back to /detect.'),
              ),
            );
          }
          apiUrl = ApiConfig.detect;
        } else {
          apiUrl = ApiConfig.detectVideo;
        }
      } else {
        apiUrl = ApiConfig.detect;
      }

      var request =
          http.MultipartRequest('POST', Uri.parse(apiUrl));

      if (_selectedVideoBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'video',
            _selectedVideoBytes!,
            filename: 'video.mp4',
          ),
        );
      } else {
        // Safety check – already guarded above but be explicit
        if (_selectedImageBytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Error: Image data is null.'),
                  backgroundColor: AppColors.error),
            );
            setState(() => _loading = false);
          }
          return;
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            _selectedImageBytes!,
            filename: 'image.jpg',
          ),
        );
      }

      if (_socialController.text.isNotEmpty) {
        request.fields['social_text'] = _socialController.text;
      }
      request.fields['lat'] = _latController.text;
      request.fields['lon'] = _lonController.text;
      request.fields['test_mode'] = _testMode.toString();

      final response = await request.send();
      final result =
          json.decode(await response.stream.bytesToString()) as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _detected = result['detected'] == true;
          _confidence =
              (result['confidence'] as num?)?.toDouble() ?? 0.0;
          _severity = (result['severity'] as String?) ?? 'none';
          _recommendation = (result['action'] as String?) ?? 'none';
          _crisisType =
              (result['crisis_type'] as String?)?.toUpperCase() ??
                  (_detected ? 'FIRE' : 'NONE');

          _currentCrisisId = result['crisis_id'] as String?;
          _allocationPlan =
              result['allocation_plan'] as Map<String, dynamic>?;
          _simulation = result['simulation'] as Map<String, dynamic>?;
          _notifications = result['notifications'] as List<dynamic>?;
          _frameResults = result['frame_results'] as List<dynamic>?;

          _loading = false;
        });

        if (_detected) {
          EventBus().fire(CrisisDetectedEvent());
        }

        if (_detected &&
            (_simulation != null ||
                _notifications != null ||
                _frameResults != null)) {
          _showResultsSheet(_simulation, _notifications, _frameResults);
        }
      }
    } catch (e) {
      if (e is SocketException || e.toString().contains('Failed host lookup') || e.toString().contains('Connection refused') || e.toString().contains('Software caused connection abort')) {
        if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Cloud detection requires internet.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      } else if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // False alarm
  // ---------------------------------------------------------------------------

  Future<void> _simulateFalseAlarm() async {
    if (_currentCrisisId == null) return;

    try {
      final url =
          '${ApiConfig.baseUrl}/retract_crisis/$_currentCrisisId';
      final response = await http.post(Uri.parse(url));

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('🛑 False alarm recorded and resources retracted.'),
              backgroundColor: AppColors.primary,
            ),
          );
          setState(() {
            _detected = false;
            _allocationPlan = null;
            _currentCrisisId = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to retract crisis: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Bottom sheet
  // ---------------------------------------------------------------------------

  void _showResultsSheet(
    Map<String, dynamic>? simulation,
    List<dynamic>? notifications,
    List<dynamic>? frameResults,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (BuildContext context) {
        final brightness = MediaQuery.of(context).platformBrightness;
        final isDarkMode = brightness == Brightness.dark;

        final sheetBg =
            isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
        final cardBg =
            isDarkMode ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);
        final textColor =
            isDarkMode ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E);
        final textSecondaryColor =
            isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF5A5A5F);
        final borderColor =
            isDarkMode ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
        final closeBtnBg =
            isDarkMode ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutQuart,
          builder: (context, animValue, child) {
            return Transform.translate(
              offset: Offset(0.0, (1.0 - animValue) * 35.0),
              child: Opacity(opacity: animValue, child: child),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF48484A)
                            : const Color(0xFFD1D1D6),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Orchestration Results',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: textColor,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: closeBtnBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: textSecondaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // -- Simulation section --
                  if (simulation != null) ...[
                    _sheetSectionLabel('SIMULATION', textSecondaryColor),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDarkMode ? 0.2 : 0.03),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Column(
                        children: [
                          _buildAppleSimulationRow(
                            emoji: '🚦',
                            label: 'ETA Reduction',
                            value:
                                '${simulation['eta_reduction_minutes'] ?? 0} min',
                            textColor: textColor,
                            textSecondaryColor: textSecondaryColor,
                          ),
                          _buildAppleDivider(borderColor),
                          _buildAppleSimulationRow(
                            emoji: '🗺️',
                            label: 'Traffic Reroute',
                            value: (simulation['traffic_reroute'] == true ||
                                    (simulation['traffic_reroute'] is Map &&
                                        simulation['traffic_reroute'] != null))
                                ? 'Active'
                                : 'Inactive',
                            textColor: textColor,
                            textSecondaryColor: textSecondaryColor,
                          ),
                          if (simulation['traffic_reroute'] is Map &&
                              simulation['traffic_reroute']
                                      ['estimated_congestion_reduction'] !=
                                  null) ...[
                            _buildAppleDivider(borderColor),
                            _buildAppleSimulationRow(
                              emoji: '📉',
                              label: 'Congestion Reduction',
                              value:
                                  '${simulation['traffic_reroute']['estimated_congestion_reduction']}',
                              textColor: textColor,
                              textSecondaryColor: textSecondaryColor,
                            ),
                          ],
                          _buildAppleDivider(borderColor),
                          _buildAppleSimulationRow(
                            emoji: '⚠️',
                            label: 'Side Effects',
                            value: '${simulation['side_effects'] ?? 'None'}',
                            textColor: textColor,
                            textSecondaryColor: textSecondaryColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // -- Notifications section --
                  if (notifications != null && notifications.isNotEmpty) ...[
                    _sheetSectionLabel('NOTIFICATIONS', textSecondaryColor),
                    ...notifications.map((n) {
                      final target =
                          (n['target'] as String?) ?? 'public';
                      final message = (n['message'] as String?) ?? '';

                      Color badgeColor;
                      switch (target.toLowerCase()) {
                        case 'public':
                          badgeColor = const Color(0xFFFF9500);
                          break;
                        case 'hospital':
                          badgeColor = const Color(0xFFFF3B30);
                          break;
                        case 'utility':
                          badgeColor = const Color(0xFF007AFF);
                          break;
                        case 'command_center':
                          badgeColor = const Color(0xFFAF52DE);
                          break;
                        default:
                          badgeColor = const Color(0xFF8E8E93);
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(isDarkMode ? 0.2 : 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(
                                    isDarkMode ? 0.15 : 0.08),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                target
                                    .toUpperCase()
                                    .replaceAll('_', ' '),
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: badgeColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              message,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                height: 1.4,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],

                  // -- Video timestamps section --
                  if (frameResults != null && frameResults.isNotEmpty) ...[
                    _sheetSectionLabel('VIDEO TIMESTAMPS', textSecondaryColor),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDarkMode ? 0.2 : 0.03),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Column(
                        children:
                            frameResults.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final frame = entry.value as Map<String, dynamic>;
                          return Column(
                            children: [
                              _buildAppleSimulationRow(
                                emoji: '⏱️',
                                label: '${frame['timestamp']}s',
                                value:
                                    '${((frame['confidence'] as num).toDouble() * 100).toStringAsFixed(1)}% Conf',
                                textColor: textColor,
                                textSecondaryColor: textSecondaryColor,
                              ),
                              if (idx < frameResults.length - 1)
                                _buildAppleDivider(borderColor),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Shared sheet helpers
  // ---------------------------------------------------------------------------

  Widget _sheetSectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }

  Widget _buildAppleSimulationRow({
    required String emoji,
    required String label,
    required String value,
    required Color textColor,
    required Color textSecondaryColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textSecondaryColor,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppleDivider(Color color) =>
      Divider(height: 1, thickness: 1, color: color);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _fetchWeather() async {
    setState(() => _loadingWeather = true);
    try {
      final lat = _latController.text.isNotEmpty ? _latController.text : "33.6844";
      final lon = _lonController.text.isNotEmpty ? _lonController.text : "73.0479";
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/weather?lat=$lat&lon=$lon'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _weatherData = json.decode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingWeather = false);
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _wsService.disconnect();
    _autoMonitorTimer?.cancel();
    _weatherTimer?.cancel();
    _socialController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _videoPlayerController?.dispose();
    // Revoke web blob URL to free memory
    if (_webVideoBlobUrl != null) {
      WebVideoHelper.revokeBlobUrl(_webVideoBlobUrl!);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Video preview builder
  // ---------------------------------------------------------------------------

  /// Builds a video preview widget that works on both web and native.
  /// - Web: VideoPlayer (video_player_web supports blob URLs), else HtmlElementView, else icon.
  /// - Native: VideoPlayer if initialized, else icon with filename.
  Widget _buildVideoPreview() {
    // VideoPlayer is initialized and ready (works on both web and native)
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      return Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _videoPlayerController!.value.aspectRatio,
            child: VideoPlayer(_videoPlayerController!),
          ),
          // Play/pause overlay icon
          GestureDetector(
            onTap: () {
              setState(() {
                _videoPlayerController!.value.isPlaying
                    ? _videoPlayerController!.pause()
                    : _videoPlayerController!.play();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _videoPlayerController!.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      );
    }

    // Web fallback: use HtmlElementView with blob URL for native <video> element
    if (kIsWeb && _webVideoBlobUrl != null) {
      return WebVideoHelper.buildVideoWidget(_webVideoBlobUrl!);
    }

    // Ultimate fallback: show icon + filename
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_file_rounded, size: 64, color: AppColors.primary),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _selectedVideoXFile?.name ??
                  _selectedVideo?.path.split('/').last ??
                  'video loaded',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '✅ Video ready — detection running',
            style: GoogleFonts.outfit(color: Colors.greenAccent, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI builders
  // ---------------------------------------------------------------------------

  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.circle, size: 12, color: Colors.green.shade500),
          const SizedBox(width: 8),
          Text(
            'CIRO ACTIVE — CLOUD MODE',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherWidget() {
    if (_loadingWeather && _weatherData == null) {
      return Container(
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8E8E93)),
          ),
        ),
      );
    }

    if (_weatherData == null) return const SizedBox.shrink();

    final temp = _weatherData!['temp_c'] ?? '--';
    final desc = _weatherData!['weather_description'] ?? _weatherData!['condition'] ?? 'Unknown';
    final icon = _weatherData!['weather_icon'] ?? '☁️';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Weather',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: const Color(0xFF8E8E93),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$temp°C · $desc',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: const Color(0xFF1C1C1E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_loadingWeather)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8E8E93)),
            ),
        ],
      ),
    );
  }

  Widget _buildContextControls() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF8F9FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Cloud Computing Mode',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF1C1C1E),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Multi-Signal Context',
            style: GoogleFonts.outfit(
              fontSize: 18, 
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 16),
          _buildWeatherWidget(),
          const SizedBox(height: 16),
          TextField(
            controller: _socialController,
            style: GoogleFonts.outfit(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Social Text (e.g., "Huge fire spreading!")',
              hintStyle: GoogleFonts.outfit(color: const Color(0xFF8E8E93)),
              filled: true,
              fillColor: const Color(0xFFF2F2F7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.outfit(fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Latitude',
                    labelStyle: GoogleFonts.outfit(color: const Color(0xFF8E8E93)),
                    filled: true,
                    fillColor: const Color(0xFFF2F2F7),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lonController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.outfit(fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Longitude',
                    labelStyle: GoogleFonts.outfit(color: const Color(0xFF8E8E93)),
                    filled: true,
                    fillColor: const Color(0xFFF2F2F7),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              title: Text(
                'Simulate Low Confidence',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1C1C1E),
                ),
              ),
              contentPadding: EdgeInsets.zero,
              value: _testMode,
              activeColor: const Color(0xFF007AFF),
              onChanged: (val) => setState(() => _testMode = val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    Color badgeColor = AppColors.success;
    IconData crisisIcon = Icons.check_circle;

    if (_detected) {
      switch (_severity) {
        case 'high':
          badgeColor = AppColors.error;
          crisisIcon = Icons.warning;
          break;
        case 'medium':
          badgeColor = AppColors.secondary ?? Colors.orange;
          crisisIcon = Icons.warning_amber;
          break;
        default:
          badgeColor = AppColors.warning;
          crisisIcon = Icons.info_outline;
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _detected
                  ? badgeColor.withOpacity(0.3)
                  : Colors.transparent,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(crisisIcon, color: badgeColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        _detected
                            ? '$_crisisType DETECTED'
                            : 'AREA CLEAR',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (_detected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor),
                      ),
                      child: Text(
                        _severity.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Confidence Level',
                    style: GoogleFonts.outfit(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                  Text(
                    '${(_confidence * 100).toStringAsFixed(1)}%',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _confidence,
                  backgroundColor: AppColors.background,
                  color: badgeColor,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recommended Action: ${_recommendation.toUpperCase()}',
                style: GoogleFonts.outfit(
                    fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        if (_detected &&
            (_simulation != null ||
                _notifications != null ||
                _frameResults != null))
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showResultsSheet(_simulation, _notifications, _frameResults),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('View Orchestration Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),

        if (_testMode && _detected)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _simulateFalseAlarm,
                icon: const Icon(Icons.block, color: AppColors.error),
                label: const Text(
                  'Simulate False Alarm',
                  style: TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBanner(),

              if (!_cameraStarted)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _startCamera,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3B30).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.videocam_rounded, color: Color(0xFFFF3B30), size: 32),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'LIVE',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1C1C1E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickVideo,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF007AFF).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF007AFF), size: 32),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'UPLOAD VIDEO',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1C1C1E),
                                  ),
                                ),
                                // Show selected filename under the button
                                if (_selectedVideoXFile != null) ...[
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text(
                                      'Selected: ${_selectedVideoXFile!.name}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: const Color(0xFF007AFF),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Camera / Video preview
                GestureDetector(
                  onTap: _startCamera,
                  child: Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Image preview (web: bytes, mobile: File)
                        if (_cameraReady && _selectedImageBytes != null)
                          kIsWeb
                              ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                              : (_selectedImage != null
                                  ? Image.file(_selectedImage!, fit: BoxFit.cover)
                                  : Image.memory(_selectedImageBytes!, fit: BoxFit.cover))
                        else if (_cameraReady && (_selectedVideoXFile != null || _selectedVideo != null))
                          _buildVideoPreview()
                        else
                          const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary),
                          ),
                        if (_loading)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _buildContextControls(),

                if (_detected || _loading) _buildResultCard(),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _startCamera,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: Text(
                          'LIVE',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B30),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickVideo,
                        icon: const Icon(Icons.upload_rounded),
                        label: Text(
                          'UPLOAD VIDEO',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF2F2F7),
                          foregroundColor: const Color(0xFF1C1C1E),
                          elevation: 0,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BoundingBoxPainter – kept for potential future use
// ---------------------------------------------------------------------------

class BoundingBoxPainter extends CustomPainter {
  final List<dynamic> detections;
  const BoundingBoxPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final det in detections) {
      final bbox = det['bbox'];
      if (bbox != null && bbox is List && bbox.length >= 4) {
        final rect = Rect.fromLTRB(
          (bbox[0] as num).toDouble() * size.width,
          (bbox[1] as num).toDouble() * size.height,
          (bbox[2] as num).toDouble() * size.width,
          (bbox[3] as num).toDouble() * size.height,
        );
        canvas.drawRect(rect, paint);

        final confidence = (det['confidence'] as num?)?.toDouble() ?? 0.0;
        textPainter.text = TextSpan(
          text:
              '${(det['label'] ?? 'FIRE').toString().toUpperCase()} ${(confidence * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.red,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.white,
          ),
        );
        textPainter.layout();
        textPainter.paint(
            canvas, Offset(rect.left, rect.top > 20 ? rect.top - 20 : 0));
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}
