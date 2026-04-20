import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a single ambient sound track
class AmbientSound {
  final String id;
  final String name;
  final String fileName; // base filename without extension
  final String emoji;
  final String description;
  final String filePath; // absolute path on disk

  const AmbientSound({
    required this.id,
    required this.name,
    required this.fileName,
    required this.emoji,
    required this.description,
    required this.filePath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'emoji': emoji,
    'description': description,
    'filePath': filePath,
  };

  factory AmbientSound.fromJson(Map<String, dynamic> json) => AmbientSound(
    id: json['id'] as String,
    name: json['name'] as String,
    fileName: json['fileName'] as String,
    emoji: json['emoji'] as String,
    description: json['description'] as String,
    filePath: json['filePath'] as String,
  );
}

/// The 5 known sound files in Nature_Pad.zip
/// Each entry: (id, fileName without ext, displayName, emoji, description)
const List<Map<String, String>> _kNaturePadSoundDefs = [
  {
    'id': 'wind_chimes',
    'fileName': 'wind_chimes',
    'name': 'Wind Chimes',
    'emoji': '🎐',
    'description': 'Delicate wind chimes swaying gently in a soft breeze',
  },
  {
    'id': 'forest_birds',
    'fileName': 'forest_birds',
    'name': 'Forest Birds',
    'emoji': '🐦',
    'description': 'Birdsong echoing through a peaceful forest canopy',
  },
  {
    'id': 'river_stream',
    'fileName': 'river_stream',
    'name': 'River Stream',
    'emoji': '🏞️',
    'description':
        'Clear water flowing over smooth stones in a mountain stream',
  },
  {
    'id': 'beach_waves',
    'fileName': 'beach_waves',
    'name': 'Beach Waves',
    'emoji': '🌊',
    'description': 'Slow rolling ocean waves washing onto a calm shore',
  },
  {
    'id': 'light_rain',
    'fileName': 'light_rain',
    'name': 'Light Rain',
    'emoji': '🌧️',
    'description': 'Gentle rain falling through a dense forest canopy',
  },
];

/// Service for managing ambient sound layer
/// Completely independent from the binaural audio engine
class AmbientSoundService {
  static const String _soundpackUrl =
      'https://lmqorzaaucvmkwlveydd.supabase.co/storage/v1/object/public/Soundpacks/Nature_Pad.zip';
  static const String _prefKeyInstalled = 'ambient_soundpack_installed';
  static const String _prefKeySelectedSound = 'ambient_selected_sound';
  static const String _prefKeyVolume = 'ambient_volume';

  static final AmbientSoundService _instance = AmbientSoundService._internal();
  factory AmbientSoundService() => _instance;
  AmbientSoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  final Dio _dio = Dio();

  bool _isPlaying = false;
  double _volume = 0.5;
  String? _selectedSoundId;
  bool _isInstalled = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _soundsDirectory;
  String? _lastError;

  List<AmbientSound> _sounds = [];

  // Stream controllers
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<double> _downloadProgressController =
      StreamController<double>.broadcast();
  final StreamController<bool> _installedController =
      StreamController<bool>.broadcast();
  final StreamController<List<AmbientSound>> _soundsController =
      StreamController<List<AmbientSound>>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  Stream<bool> get playingStream => _playingController.stream;
  Stream<double> get downloadProgressStream =>
      _downloadProgressController.stream;
  Stream<bool> get installedStream => _installedController.stream;
  Stream<List<AmbientSound>> get soundsStream => _soundsController.stream;
  Stream<String?> get errorStream => _errorController.stream;

  bool get isPlaying => _isPlaying;
  double get volume => _volume;
  String? get selectedSoundId => _selectedSoundId;
  bool get isInstalled => _isInstalled;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get lastError => _lastError;

  /// All available ambient sounds (populated after install)
  List<AmbientSound> get availableSounds => _sounds;

  /// Returns which sound IDs have been successfully resolved on disk
  Set<String> get installedSoundIds => _sounds.map((s) => s.id).toSet();

  /// Initialize service and restore state
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _volume = prefs.getDouble(_prefKeyVolume) ?? 0.5;
      _selectedSoundId = prefs.getString(_prefKeySelectedSound);
      _isInstalled = prefs.getBool(_prefKeyInstalled) ?? false;

      await _player.setVolume(_volume);

      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        _soundsDirectory = '${dir.path}/ambient_sounds';

        if (_isInstalled) {
          await _buildSoundList();

          if (_sounds.isEmpty) {
            _isInstalled = false;
            await prefs.setBool(_prefKeyInstalled, false);
          }
        }
      }
    } catch (e) {
      debugPrint('AmbientSoundService init error: $e');
    }
  }

  /// Build the sound list from the known filenames, validating each file exists
  Future<void> _buildSoundList() async {
    if (kIsWeb || _soundsDirectory == null) return;
    _sounds = [];

    for (final def in _kNaturePadSoundDefs) {
      final filePath = '$_soundsDirectory/${def['fileName']}.mp3';
      final exists = await File(filePath).exists();
      if (exists) {
        _sounds.add(
          AmbientSound(
            id: def['id']!,
            name: def['name']!,
            fileName: def['fileName']!,
            emoji: def['emoji']!,
            description: def['description']!,
            filePath: filePath,
          ),
        );
        debugPrint('AmbientSoundService: found "${def['fileName']}.mp3"');
      } else {
        debugPrint(
          'AmbientSoundService: missing "${def['fileName']}.mp3" at $filePath',
        );
      }
    }

    debugPrint('AmbientSoundService: ${_sounds.length}/5 sounds available');
    _soundsController.add(_sounds);
  }

  /// Download and install the soundpack
  Future<bool> downloadAndInstall({
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      debugPrint('Ambient sound download not supported on web');
      return false;
    }
    if (_isDownloading) return false;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _downloadProgressController.add(0.0);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${dir.path}/ambient_sounds');
      final zipPath = '${dir.path}/nature_pad.zip';

      // Download zip
      await _dio.download(
        _soundpackUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress = received / total * 0.8;
            _downloadProgressController.add(_downloadProgress);
            onProgress?.call(_downloadProgress);
          }
        },
      );

      // Extract zip
      _downloadProgress = 0.85;
      _downloadProgressController.add(_downloadProgress);
      onProgress?.call(_downloadProgress);

      if (!await soundsDir.exists()) {
        await soundsDir.create(recursive: true);
      }

      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      int extractedCount = 0;
      for (final file in archive) {
        if (!file.isFile) continue;
        // Get just the filename (strip any folder path inside zip)
        final parts = file.name.replaceAll('\\', '/').split('/');
        final fileName = parts.last;
        if (fileName.isEmpty || fileName.startsWith('.')) continue;
        final ext = fileName.contains('.')
            ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase()
            : '';
        if (['.mp3', '.wav', '.ogg', '.aac', '.m4a', '.flac'].contains(ext)) {
          final outFile = File('${soundsDir.path}/$fileName');
          final fileBytes = file.readBytes();
          await outFile.writeAsBytes(fileBytes ?? []);
          extractedCount++;
          debugPrint('AmbientSoundService: extracted "$fileName"');
        }
      }

      debugPrint(
        'AmbientSoundService: extracted $extractedCount audio files total',
      );

      // Cleanup zip
      try {
        await File(zipPath).delete();
      } catch (_) {}

      _soundsDirectory = soundsDir.path;

      // Build sound list from known filenames
      await _buildSoundList();

      _isInstalled = _sounds.isNotEmpty;
      _downloadProgress = 1.0;
      _downloadProgressController.add(1.0);
      onProgress?.call(1.0);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyInstalled, _isInstalled);
      _installedController.add(_isInstalled);

      return _isInstalled;
    } catch (e) {
      final errorMsg =
          'Download failed: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Error downloading soundpack: $e');
      _lastError = errorMsg;
      _errorController.add(errorMsg);
      _downloadProgress = 0.0;
      _downloadProgressController.add(0.0);
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// Select a sound by id
  Future<void> selectSound(String soundId) async {
    _selectedSoundId = soundId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySelectedSound, soundId);

    if (_isPlaying) {
      await _loadAndPlay(soundId);
    }
  }

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKeyVolume, _volume);
  }

  /// Start ambient playback
  Future<bool> play() async {
    if (kIsWeb) return false;
    if (_selectedSoundId == null) return false;
    return await _loadAndPlay(_selectedSoundId!);
  }

  Future<bool> _loadAndPlay(String soundId) async {
    try {
      final sound = _sounds.firstWhere(
        (s) => s.id == soundId,
        orElse: () => throw Exception('Sound not found: $soundId'),
      );
      await _player.stop();
      await _player.setFilePath(sound.filePath);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(_volume);
      await _player.play();
      _isPlaying = true;
      _playingController.add(true);
      return true;
    } catch (e) {
      debugPrint('Error playing ambient sound: $e');
      _isPlaying = false;
      _playingController.add(false);
      return false;
    }
  }

  /// Stop ambient playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _playingController.add(false);
    } catch (e) {
      debugPrint('Error stopping ambient sound: $e');
    }
  }

  /// Toggle play/stop
  Future<bool> togglePlayStop() async {
    if (_isPlaying) {
      await stop();
      return false;
    } else {
      return await play();
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _player.dispose();
    await _playingController.close();
    await _downloadProgressController.close();
    await _installedController.close();
    await _soundsController.close();
    await _errorController.close();
  }
}