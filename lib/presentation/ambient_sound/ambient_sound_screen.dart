import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sizer/sizer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ambient_sound_service.dart';

class AmbientSoundScreen extends StatefulWidget {
  const AmbientSoundScreen({super.key});

  @override
  State<AmbientSoundScreen> createState() => _AmbientSoundScreenState();
}

class _AmbientSoundScreenState extends State<AmbientSoundScreen>
    with TickerProviderStateMixin {
  final AmbientSoundService _service = AmbientSoundService();

  bool _isInitialized = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isPlaying = false;
  double _volume = 0.5;
  String? _selectedSoundId;
  bool _isInstalled = false;
  String? _errorMessage;
  List<AmbientSound> _sounds = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initService();
  }

  Future<void> _initService() async {
    await _service.initialize();
    if (mounted) {
      setState(() {
        _isInstalled = _service.isInstalled;
        _volume = _service.volume;
        _sounds = _service.availableSounds;
        _selectedSoundId =
            _service.selectedSoundId ??
            (_sounds.isNotEmpty ? _sounds.first.id : null);
        _isPlaying = _service.isPlaying;
        _isInitialized = true;
      });
    }

    // Listen for sounds updates (after download)
    _service.soundsStream.listen((sounds) {
      if (mounted) {
        setState(() {
          _sounds = sounds;
          if (_selectedSoundId == null && sounds.isNotEmpty) {
            _selectedSoundId = sounds.first.id;
          }
        });
      }
    });
  }

  Future<void> _downloadSoundpack() async {
    if (kIsWeb) {
      setState(() {
        _errorMessage =
            'Sound download is not supported in the web preview. Please test on a physical device.';
      });
      return;
    }
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    final success = await _service.downloadAndInstall(
      onProgress: (progress) {
        if (mounted) {
          setState(() => _downloadProgress = progress);
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDownloading = false;
        _isInstalled = _service.isInstalled;
        _sounds = _service.availableSounds;
        if (_selectedSoundId == null && _sounds.isNotEmpty) {
          _selectedSoundId = _sounds.first.id;
        }
        if (!success) {
          _errorMessage =
              _service.lastError ??
              'Failed to download soundpack. Please check your connection and try again.';
        }
      });
    }
  }

  Future<void> _selectAndPlay(String soundId) async {
    if (!_isInstalled) return;
    final wasPlaying = _isPlaying;
    setState(() => _selectedSoundId = soundId);
    await _service.selectSound(soundId);
    if (!wasPlaying) {
      final nowPlaying = await _service.play();
      if (mounted) setState(() => _isPlaying = nowPlaying);
    }
  }

  Future<void> _togglePlay() async {
    if (_selectedSoundId == null || !_isInstalled) return;
    if (_selectedSoundId != _service.selectedSoundId) {
      await _service.selectSound(_selectedSoundId!);
    }
    final nowPlaying = await _service.togglePlayStop();
    if (mounted) setState(() => _isPlaying = nowPlaying);
  }

  Future<void> _updateVolume(double value) async {
    setState(() => _volume = value);
    await _service.setVolume(value);
  }

  AmbientSound? get _selectedSound {
    if (_selectedSoundId == null || _sounds.isEmpty) return null;
    try {
      return _sounds.firstWhere((s) => s.id == _selectedSoundId);
    } catch (_) {
      return _sounds.isNotEmpty ? _sounds.first : null;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF7B8CDE),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ambient Sounds',
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isInstalled && _sounds.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: 3.w),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 2.5.w,
                    vertical: 0.4.h,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2640),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: Text(
                    '${_sounds.length} sounds',
                    style: GoogleFonts.dmSans(
                      color: const Color(0xFF7B8CDE),
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1E2640)),
        ),
      ),
      body: !_isInitialized
          ? _buildLoadingState()
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isInstalled) ...[
                    _buildInstallCard(),
                    SizedBox(height: 2.h),
                    _buildSoundPreviewList(),
                  ] else ...[
                    _buildNowPlayingCard(),
                    SizedBox(height: 2.h),
                    _buildVolumeCard(),
                    SizedBox(height: 2.h),
                    _buildSoundSelectorSection(),
                  ],
                  if (_errorMessage != null) ...[
                    SizedBox(height: 2.h),
                    _buildErrorCard(),
                  ],
                  SizedBox(height: 3.h),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF7B8CDE),
            strokeWidth: 2,
          ),
          SizedBox(height: 2.h),
          Text(
            'Initializing...',
            style: GoogleFonts.dmSans(
              color: const Color(0xFF7B8CDE),
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: const Color(0xFF1E2640), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(2.w),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B8CDE).withAlpha(30),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: const Icon(
                  Icons.download_rounded,
                  color: Color(0xFF7B8CDE),
                  size: 22,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nature Pad Soundpack',
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Ambient sounds • Nature series',
                      style: GoogleFonts.dmSans(
                        color: const Color(0xFF6B7280),
                        fontSize: 9.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 1.5.h),
          Text(
            'Download the Nature Pad soundpack to unlock all ambient sounds for layering with your binaural sessions.',
            style: GoogleFonts.dmSans(
              color: const Color(0xFF6B7280),
              fontSize: 10.sp,
              height: 1.5,
            ),
          ),
          SizedBox(height: 2.h),
          if (_isDownloading) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: const Color(0xFF1E2640),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF7B8CDE),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                SizedBox(width: 3.w),
                Text(
                  '${(_downloadProgress * 100).toInt()}%',
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFF7B8CDE),
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 1.h),
            Text(
              _downloadProgress < 0.82
                  ? 'Downloading soundpack...'
                  : 'Extracting sounds...',
              style: GoogleFonts.dmSans(
                color: const Color(0xFF6B7280),
                fontSize: 9.sp,
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _downloadSoundpack,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  'Download & Install Sounds',
                  style: GoogleFonts.dmSans(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B8CDE),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 1.5.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Preview list shown before install — placeholder locked cards
  Widget _buildSoundPreviewList() {
    // Show the exact 5 sounds from Nature_Pad.zip
    final placeholders = [
      ('🎐', 'Wind Chimes'),
      ('🐦', 'Forest Birds'),
      ('🏞️', 'River Stream'),
      ('🌊', 'Beach Waves'),
      ('🌧️', 'Light Rain'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 1.w, bottom: 1.h),
          child: Text(
            'INCLUDED SOUNDS',
            style: GoogleFonts.dmSans(
              color: const Color(0xFF4A5568),
              fontSize: 9.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...placeholders.map(
          (p) => Padding(
            padding: EdgeInsets.only(bottom: 1.h),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: const Color(0xFF1E2640), width: 1),
              ),
              child: Row(
                children: [
                  Text(p.$1, style: TextStyle(fontSize: 18.sp)),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: Text(
                      p.$2,
                      style: GoogleFonts.dmSans(
                        color: const Color(0xFF6B7280),
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF374151),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNowPlayingCard() {
    final sound = _selectedSound;
    if (sound == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: _isPlaying
              ? const Color(0xFF7B8CDE).withAlpha(80)
              : const Color(0xFF1E2640),
          width: 1,
        ),
        boxShadow: _isPlaying
            ? [
                BoxShadow(
                  color: const Color(0xFF7B8CDE).withAlpha(20),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isPlaying ? _pulseAnimation.value : 1.0,
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 14.w,
                    height: 14.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isPlaying
                            ? [const Color(0xFF7B8CDE), const Color(0xFF5B6BBE)]
                            : [
                                const Color(0xFF2D3748),
                                const Color(0xFF1E2640),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: _isPlaying
                          ? [
                              BoxShadow(
                                color: const Color(0xFF7B8CDE).withAlpha(80),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 6.w,
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPlaying ? 'NOW PLAYING' : 'SELECTED',
                  style: GoogleFonts.dmSans(
                    color: _isPlaying
                        ? const Color(0xFF7B8CDE)
                        : const Color(0xFF4A5568),
                    fontSize: 8.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 0.3.h),
                Row(
                  children: [
                    Text(sound.emoji, style: TextStyle(fontSize: 14.sp)),
                    SizedBox(width: 2.w),
                    Expanded(
                      child: Text(
                        sound.name,
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 0.3.h),
                Text(
                  sound.description,
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFF6B7280),
                    fontSize: 9.sp,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          if (_isPlaying)
            Container(
              width: 2.w,
              height: 2.w,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF34D399),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVolumeCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: const Color(0xFF1E2640), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _volume < 0.01
                        ? Icons.volume_off_rounded
                        : _volume < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                    color: const Color(0xFF7B8CDE),
                    size: 18,
                  ),
                  SizedBox(width: 2.w),
                  Text(
                    'Master Volume',
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 2.5.w,
                  vertical: 0.5.h,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2640),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Text(
                  '${(_volume * 100).toInt()}%',
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFF7B8CDE),
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 1.5.h),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF7B8CDE),
              inactiveTrackColor: const Color(0xFF1E2640),
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF7B8CDE).withAlpha(40),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
              trackHeight: 4.0,
            ),
            child: Slider(
              value: _volume,
              min: 0.0,
              max: 1.0,
              onChanged: _updateVolume,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Silent',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF4A5568),
                  fontSize: 9.sp,
                ),
              ),
              Text(
                'Full',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF4A5568),
                  fontSize: 9.sp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSoundSelectorSection() {
    if (_sounds.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Text(
            'No sounds found. Please re-download the soundpack.',
            style: GoogleFonts.dmSans(
              color: const Color(0xFF6B7280),
              fontSize: 11.sp,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 1.w, bottom: 1.5.h),
          child: Row(
            children: [
              const Icon(
                Icons.library_music_rounded,
                color: Color(0xFF7B8CDE),
                size: 16,
              ),
              SizedBox(width: 2.w),
              Text(
                'SELECT SOUND',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF9CA3AF),
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${_sounds.length} tracks',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF4A5568),
                  fontSize: 9.sp,
                ),
              ),
            ],
          ),
        ),
        ..._sounds.map((sound) {
          final isSelected = _selectedSoundId == sound.id;
          final isCurrentlyPlaying = isSelected && _isPlaying;

          return Padding(
            padding: EdgeInsets.only(bottom: 1.2.h),
            child: GestureDetector(
              onTap: () => _selectAndPlay(sound.id),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.8.h),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF7B8CDE).withAlpha(25)
                      : const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(14.0),
                  border: Border.all(
                    color: isCurrentlyPlaying
                        ? const Color(0xFF7B8CDE).withAlpha(120)
                        : isSelected
                        ? const Color(0xFF7B8CDE).withAlpha(60)
                        : const Color(0xFF1E2640),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Emoji icon
                    Container(
                      width: 11.w,
                      height: 11.w,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF7B8CDE).withAlpha(40)
                            : const Color(0xFF1A2035),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Center(
                        child: Text(
                          sound.emoji,
                          style: TextStyle(fontSize: 16.sp),
                        ),
                      ),
                    ),
                    SizedBox(width: 3.w),
                    // Name + filename
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sound.name,
                            style: GoogleFonts.dmSans(
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF9CA3AF),
                              fontSize: 12.sp,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          SizedBox(height: 0.3.h),
                          Text(
                            sound.description,
                            style: GoogleFonts.dmSans(
                              color: isSelected
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF4A5568),
                              fontSize: 9.sp,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 2.w),
                    // Status indicator
                    if (isCurrentlyPlaying)
                      Container(
                        padding: EdgeInsets.all(1.5.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B8CDE).withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: Color(0xFF7B8CDE),
                          size: 16,
                        ),
                      )
                    else if (isSelected)
                      Container(
                        padding: EdgeInsets.all(1.5.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B8CDE).withAlpha(20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF7B8CDE),
                          size: 16,
                        ),
                      )
                    else
                      const Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: Color(0xFF2D3748),
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E0E),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
          color: const Color(0xFF7F1D1D).withAlpha(120),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 18,
          ),
          SizedBox(width: 2.w),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.dmSans(
                color: const Color(0xFFEF4444),
                fontSize: 10.sp,
                height: 1.4,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: const Icon(
              Icons.close_rounded,
              color: Color(0xFF6B7280),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}
