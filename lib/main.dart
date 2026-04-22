import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const FindCarApp());
}

class FindCarApp extends StatelessWidget {
  const FindCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FIND CAR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _isHebrew = false;
  bool _hasSavedSpot = false;
  bool _isSaving = false;
  double? _savedLat;
  double? _savedLng;
  DateTime? _savedAt;
  String? _permissionError;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    final locale = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _isHebrew = locale == 'he' || locale == 'iw';
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _loadSavedSpot();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSpot() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('lat');
    final lng = prefs.getDouble('lng');
    final savedAtMs = prefs.getInt('savedAt');
    if (lat != null && lng != null) {
      setState(() {
        _savedLat = lat;
        _savedLng = lng;
        _hasSavedSpot = true;
        _savedAt = savedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(savedAtMs) : null;
      });
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _permissionError = _isHebrew
          ? 'שירות המיקום כבוי. אנא הפעל מיקום בהגדרות הטלפון.'
          : 'Location services are disabled. Please enable them in Settings.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _permissionError = _isHebrew
            ? 'הרשאת מיקום נדחתה. אנא אפשר גישה למיקום.'
            : 'Location permission denied. Please allow access.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _permissionError = _isHebrew
          ? kIsWeb
              ? 'הרשאת מיקום נחסמה. אפשר מיקום בהגדרות הדפדפן.'
              : 'הרשאת מיקום נחסמה. פתח הגדרות ואפשר מיקום ידנית.'
          : kIsWeb
              ? 'Location permission blocked. Allow location in browser settings.'
              : 'Location permission permanently denied. Open Settings to allow access.');
      if (!kIsWeb) _showOpenSettingsDialog();
      return false;
    }

    setState(() => _permissionError = null);
    return true;
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isHebrew ? 'נדרשת הרשאת מיקום' : 'Location Permission Required'),
        content: Text(_isHebrew
            ? 'אנא פתח הגדרות ואפשר גישה למיקום עבור FIND CAR.'
            : 'Please open Settings and allow location access for FIND CAR.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isHebrew ? 'ביטול' : 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: Text(_isHebrew ? 'פתח הגדרות' : 'Open Settings',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSpot() async {
    setState(() { _isSaving = true; _permissionError = null; });

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      setState(() => _isSaving = false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('lat', position.latitude);
      await prefs.setDouble('lng', position.longitude);
      await prefs.setInt('savedAt', DateTime.now().millisecondsSinceEpoch);
      if (!kIsWeb) HapticFeedback.heavyImpact();
      setState(() {
        _savedLat = position.latitude;
        _savedLng = position.longitude;
        _savedAt = DateTime.now();
        _hasSavedSpot = true;
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _permissionError = _isHebrew
            ? 'אין קליטה.'
            : 'Could not get location. no signal.';
        _isSaving = false;
      });
    }
  }

  Future<void> _navigate() async {
    if (_savedLat == null || _savedLng == null) return;
    if (!kIsWeb) HapticFeedback.mediumImpact();
    final wazeUrl = 'waze://?ll=$_savedLat,$_savedLng&navigate=yes';
    final googleUrl = 'https://www.google.com/maps/dir/?api=1&destination=$_savedLat,$_savedLng&travelmode=walking';
    if (await canLaunchUrl(Uri.parse(wazeUrl))) {
      await launchUrl(Uri.parse(wazeUrl));
    } else {
      await launchUrl(Uri.parse(googleUrl), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _clearSpot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lat');
    await prefs.remove('lng');
    await prefs.remove('savedAt');
    if (!kIsWeb) HapticFeedback.lightImpact();
    setState(() { _hasSavedSpot = false; _savedLat = null; _savedLng = null; _savedAt = null; _permissionError = null; });
  }

  String _timeAgo() {
    if (_savedAt == null) return '';
    final diff = DateTime.now().difference(_savedAt!);
    if (diff.inMinutes < 1) return _isHebrew ? 'עכשיו' : 'just now';
    if (diff.inMinutes < 60) return _isHebrew ? 'לפני ${diff.inMinutes} דקות' : '${diff.inMinutes}m ago';
    return _isHebrew ? 'לפני ${diff.inHours} שעות' : '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('FIND CAR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 2)),
                      GestureDetector(
                        onTap: () => setState(() => _isHebrew = !_isHebrew),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(20)),
                          child: Text(_isHebrew ? 'English' : 'עברית', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ScaleTransition(
                        scale: _hasSavedSpot ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
                        child: Text(_hasSavedSpot ? '✅' : '🚗', style: const TextStyle(fontSize: 72)),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _hasSavedSpot ? (_isHebrew ? 'הרכב שמור!' : 'Car saved!') : (_isHebrew ? 'איפה חנית?' : 'Where did you park?'),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _hasSavedSpot
                            ? (_isHebrew ? 'לחץ על הכפתור הכחול כדי לחזור לרכב' : 'Tap the blue button to go back to your car')
                            : (_isHebrew ? 'לחץ שמור ברגע שחנית.\nנמצא אותך אחר כך.' : 'Press Save the moment you park.\nWe\'ll find you later.'),
                        style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      if (_hasSavedSpot && _savedAt != null) ...[
                        const SizedBox(height: 8),
                        Text(_timeAgo(), style: const TextStyle(fontSize: 13, color: Colors.black38)),
                      ],
                      if (_hasSavedSpot && _savedLat != null && _savedLng != null) ...[
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            height: 200,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: LatLng(_savedLat!, _savedLng!),
                                initialZoom: 16,
                                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'find.car',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: LatLng(_savedLat!, _savedLng!),
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.directions_car, color: Colors.black, size: 36),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_permissionError != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_off, color: Colors.red.shade700, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_permissionError!, style: TextStyle(fontSize: 13, color: Colors.red.shade700))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!kIsWeb)
                          GestureDetector(
                            onTap: Geolocator.openAppSettings,
                            child: Text(
                              _isHebrew ? 'פתח הגדרות' : 'Open Settings',
                              style: const TextStyle(fontSize: 13, color: Colors.black54, decoration: TextDecoration.underline),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (!_hasSavedSpot)
                      _BigButton(
                        label: _isSaving ? (_isHebrew ? 'תופס מיקום...' : 'Getting location...') : (_isHebrew ? '📍  שמור את המיקום שלי' : '📍  Save my spot'),
                        color: Colors.black,
                        textColor: Colors.white,
                        onTap: _isSaving ? null : _saveSpot,
                      ),
                    if (_hasSavedSpot) ...[
                      _BigButton(
                        label: _isHebrew ? '🗺️  קח אותי לרכב' : '🗺️  Take me to my car',
                        color: const Color(0xFF1a73e8),
                        textColor: Colors.white,
                        onTap: _navigate,
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _clearSpot,
                        child: Text(
                          _isHebrew ? 'חניתי במקום חדש' : 'Parked somewhere new',
                          style: const TextStyle(fontSize: 14, color: Colors.black45, decoration: TextDecoration.underline, decorationColor: Colors.black45),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;
  const _BigButton({required this.label, required this.color, required this.textColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 68,
        decoration: BoxDecoration(
          color: onTap == null ? color.withOpacity(0.4) : color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(child: Text(label, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: textColor))),
      ),
    );
  }
}