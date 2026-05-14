import 'dart:io' show Platform;

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
  bool _mapReady = false;
  double? _savedLat;
  double? _savedLng;
  DateTime? _savedAt;
  String? _permissionError;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    final locale = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _isHebrew = locale == 'he' || locale == 'iw';
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _mapController = MapController();
    _loadSavedSpot();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
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
    setState(() { _isSaving = true; _permissionError = null; _mapReady = false; });

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
        _permissionError = _isHebrew ? 'אין קליטה.' : 'Could not get location. No signal.';
        _isSaving = false;
      });
    }
  }

  // ─── ניווט: תמיד מציג picker עם כל האפליקציות הזמינות ──────────────────
  Future<void> _navigate() async {
    if (_savedLat == null || _savedLng == null) return;
    if (!kIsWeb) HapticFeedback.mediumImpact();

    final lat = _savedLat!;
    final lng = _savedLng!;
    final bool isIOS = !kIsWeb && Platform.isIOS;

    final wazeUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    final googleUri = isIOS
        ? Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=walking')
        : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking');

    final wazeAvailable = await canLaunchUrl(wazeUri);
    final googleAvailable = await canLaunchUrl(googleUri);

    if (!mounted) return;

    // בונים רשימת אפליקציות זמינות — Apple Maps תמיד קיים באייפון
    final options = <_NavItem>[
      if (wazeAvailable) _NavItem('🚗', _isHebrew ? 'וייז' : 'Waze', wazeUri),
      if (googleAvailable) _NavItem('🗺️', _isHebrew ? 'גוגל מפות' : 'Google Maps', googleUri),
      if (isIOS) _NavItem('🍎', _isHebrew ? 'אפל מפות' : 'Apple Maps',
          Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=w')),
    ];

    if (options.isEmpty) return;

    // אפשרות אחת בלבד — פותחים ישירות
    if (options.length == 1) {
      await launchUrl(options.first.uri, mode: LaunchMode.externalApplication);
      return;
    }

    // מספר אפשרויות — מציגים picker לבחירה
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Text(
                _isHebrew ? 'פתח עם...' : 'Open with...',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              ...options.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NavOption(
                  icon: opt.icon,
                  label: opt.label,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await launchUrl(opt.uri, mode: LaunchMode.externalApplication);
                  },
                ),
              )),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearSpot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isHebrew ? 'מחיקת מיקום' : 'Clear spot'),
        content: Text(_isHebrew ? 'חנית במקום חדש?' : 'Did you park somewhere new?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isHebrew ? 'ביטול' : 'Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isHebrew ? 'כן, מחק' : 'Yes, clear',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lat');
    await prefs.remove('lng');
    await prefs.remove('savedAt');
    if (!kIsWeb) HapticFeedback.lightImpact();
    setState(() {
      _hasSavedSpot = false;
      _savedLat = null;
      _savedLng = null;
      _savedAt = null;
      _permissionError = null;
      _mapReady = false;
    });
  }

  String _timeAgo() {
    if (_savedAt == null) return '';
    final diff = DateTime.now().difference(_savedAt!);
    if (diff.inMinutes < 1) return _isHebrew ? 'עכשיו' : 'just now';
    if (diff.inMinutes < 60) return _isHebrew ? 'לפני ${diff.inMinutes} דקות' : '${diff.inMinutes}m ago';
    return _isHebrew ? 'לפני ${diff.inHours} שעות' : '${diff.inHours}h ago';
  }

  // ─── מסך מפה מלאה עם כפתורים צפים ──────────────────────────────────────
  Widget _buildMapScreen() {
    return Stack(
      children: [
        // מפה על מסך מלא — נטענת ברקע, מוצגת רק כשמוכנה
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(_savedLat!, _savedLng!),
            initialZoom: 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
            onMapReady: () {
              setState(() => _mapReady = true);
            },
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
                  width: 56,
                  height: 56,
                  child: ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: const Icon(Icons.directions_car, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Loading indicator — ספינר קטן בפינה עד שהמפה טעונה
        if (!_mapReady)
          const Positioned(
            top: 60,
            right: 20,
            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
          ),

        // ─── כפתור מרכוז מפה גדול (נגיש לזקנים) ───
        Positioned(
          right: 20,
          bottom: 240,
          child: GestureDetector(
            onTap: () => _mapController.move(LatLng(_savedLat!, _savedLng!), 17),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.my_location, size: 34, color: Colors.black87),
            ),
          ),
        ),

        // ─── כפתורים תחתונים ───
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_savedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                        ),
                        child: Text(
                          '${_isHebrew ? "חנית" : "Saved"} ${_timeAgo()}',
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ),
                    ),
                  // כפתור ניווט
                  GestureDetector(
                    onTap: _navigate,
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a73e8),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF1a73e8).withOpacity(0.45), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _isHebrew ? '🗺️  קח אותי לרכב' : '🗺️  Take me to my car',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // כפתור מצאתי את הרכב
                  GestureDetector(
                    onTap: _clearSpot,
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF2E7D32), width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Center(
                        child: Text(
                          _isHebrew ? '✅  מצאתי את הרכב!' : '✅  I found my car!',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // שגיאה
        if (_permissionError != null)
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Container(
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
          ),
      ],
    );
  }

  // ─── מסך ראשי (אין מיקום שמור) ──────────────────────────────────────────
  Widget _buildHomeScreen() {
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
                      const Text('🚗', style: TextStyle(fontSize: 80)),
                      const SizedBox(height: 24),
                      Text(
                        _isHebrew ? 'איפה חנית?' : 'Where did you park?',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isHebrew
                            ? 'לחץ שמור ברגע שחנית.\nנמצא אותך אחר כך.'
                            : 'Press Save the moment you park.\nWe\'ll find you later.',
                        style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.6),
                        textAlign: TextAlign.center,
                      ),
                      if (_permissionError != null) ...[
                        const SizedBox(height: 20),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: GestureDetector(
                    onTap: _isSaving ? null : _saveSpot,
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _isSaving ? Colors.black38 : Colors.black,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _isSaving ? [] : [
                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _isSaving
                              ? (_isHebrew ? 'תופס מיקום...' : 'Getting location...')
                              : (_isHebrew ? '📍  שמור את המיקום שלי' : '📍  Save my spot'),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSavedSpot && _savedLat != null && _savedLng != null) {
      return Directionality(
        textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: _buildMapScreen()),
      );
    }
    return _buildHomeScreen();
  }
}

// ─── מודל אפשרות ניווט ──────────────────────────────────────────────────────
class _NavItem {
  final String icon;
  final String label;
  final Uri uri;
  const _NavItem(this.icon, this.label, this.uri);
}

// ─── ווידג'ט אפשרות ניווט ───────────────────────────────────────────────────
class _NavOption extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _NavOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}