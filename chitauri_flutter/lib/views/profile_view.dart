import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../theme/pulse_theme.dart';

class ProfileView extends StatefulWidget {
  final List<Track> tracks;

  const ProfileView({
    super.key,
    required this.tracks,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  String _userName = 'Music Lover';
  String _favoriteGenre = 'Pop & Acoustic';

  int get _trackCount => widget.tracks.length;
  int get _totalBytes => widget.tracks.fold<int>(0, (sum, t) => sum + (t.fileSize > 0 ? t.fileSize : 0));

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_profile_name') ?? 'Music Lover';
    final genre = prefs.getString('user_favorite_genre') ?? 'All Genres';

    if (mounted) {
      setState(() {
        _userName = name;
        _favoriteGenre = genre;
      });
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _userName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Your Name', style: TextStyle(color: PulseColors.textWhite, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: PulseColors.textWhite),
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: PulseColors.textMuted),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: PulseColors.primaryMint)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: PulseColors.primaryMint, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: PulseColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
            child: const Text('Save', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_profile_name', newName);
      setState(() {
        _userName = newName;
      });
    }
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: PulseColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(color: PulseColors.textWhite, fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
            child: const Text('Close', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mb = (_totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Clean Profile Section Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  PulseColors.primaryMint.withOpacity(0.18),
                  PulseColors.surfaceContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PulseColors.primaryMint.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PulseColors.textWhite,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: _editName,
                            child: const Icon(Icons.edit, color: PulseColors.primaryMint, size: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Offline Music Member',
                        style: TextStyle(
                          color: PulseColors.primaryMint,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Simple Statistics Overview
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PulseColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.music_note, color: PulseColors.primaryMint, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        '$_trackCount',
                        style: const TextStyle(color: PulseColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      const Text('Downloaded Songs', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PulseColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.folder_outlined, color: PulseColors.primaryMint, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        '$mb MB',
                        style: const TextStyle(color: PulseColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      const Text('Storage Saved', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. About You Section
          const Text(
            'ABOUT YOU',
            style: TextStyle(
              color: PulseColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline, color: PulseColors.primaryMint),
                  title: const Text('Name', style: TextStyle(color: PulseColors.textWhite, fontSize: 14)),
                  subtitle: Text(_userName, style: const TextStyle(color: PulseColors.textMuted, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: PulseColors.textMuted),
                  onTap: _editName,
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                ListTile(
                  leading: const Icon(Icons.queue_music, color: PulseColors.primaryMint),
                  title: const Text('Music Taste', style: TextStyle(color: PulseColors.textWhite, fontSize: 14)),
                  subtitle: Text(_favoriteGenre, style: const TextStyle(color: PulseColors.textMuted, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: PulseColors.textMuted),
                  onTap: () async {
                    final genres = ['All Music', 'Rock & Classics', 'Pop & Melodies', 'Hip-Hop & R&B', 'Acoustic & Classical', 'Electronic'];
                    final selected = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        backgroundColor: PulseColors.surfaceContainerHigh,
                        title: const Text('Select Music Taste', style: TextStyle(color: PulseColors.textWhite)),
                        children: genres.map((g) => SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, g),
                          child: Text(g, style: const TextStyle(color: PulseColors.textWhite)),
                        )).toList(),
                      ),
                    );
                    if (selected != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('user_favorite_genre', selected);
                      setState(() => _favoriteGenre = selected);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 4. Legal & App Information Section
          const Text(
            'ABOUT & LEGAL',
            style: TextStyle(
              color: PulseColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: PulseColors.primaryMint),
                  title: const Text('Privacy Policy', style: TextStyle(color: PulseColors.textWhite, fontSize: 14)),
                  subtitle: const Text('Your data stays 100% on your device', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, color: PulseColors.textMuted),
                  onTap: () {
                    _showInfoDialog(
                      'Privacy Policy',
                      'Your privacy is our priority.\n\n'
                      '• Zero Data Collection: Chitauri does not track, collect, or share any personal information.\n'
                      '• Local Storage Only: All downloaded audio tracks, playlists, and favorites are stored strictly on your device.\n'
                      '• No External Logins: You are free to browse and enjoy your offline music library without creating an account or logging in.\n'
                      '• Direct Connection: When downloading songs, Chitauri connects directly to client streams with zero intermediary proxy servers.',
                    );
                  },
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined, color: PulseColors.primaryMint),
                  title: const Text('Terms & Conditions', style: TextStyle(color: PulseColors.textWhite, fontSize: 14)),
                  subtitle: const Text('Simple personal use terms', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, color: PulseColors.textMuted),
                  onTap: () {
                    _showInfoDialog(
                      'Terms & Conditions',
                      'Welcome to Chitauri Audio Suite.\n\n'
                      '1. Personal Use: This application is designed for personal offline listening and educational purposes.\n'
                      '2. Content Ownership: All music rights and copyright belong to their respective creators and artists. Please support the artists by purchasing official records and attending concerts.\n'
                      '3. Offline Playback: You are responsible for the media stored on your personal phone storage.\n'
                      '4. Safe & Ad-Free: The app provides zero intrusive ads, clean playback controls, and client-side hardware decoding.',
                    );
                  },
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: PulseColors.primaryMint),
                  title: const Text('About Chitauri', style: TextStyle(color: PulseColors.textWhite, fontSize: 14)),
                  subtitle: const Text('Version 1.2 • High Fidelity Audio Player', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, color: PulseColors.textMuted),
                  onTap: () {
                    _showInfoDialog(
                      'About Chitauri',
                      'Chitauri Audio Suite v1.2\n\n'
                      'A lightweight, high-fidelity native music suite designed for effortless YouTube audio grabbing and offline listening.\n\n'
                      'Features:\n'
                      '• 3-Tier Fallback Download Architecture\n'
                      '• Space-saving 3.5MB audio files\n'
                      '• Lock Screen, Bluetooth & Notification controls\n'
                      '• Vinyl turntable & interactive equalizer\n'
                      '• Dedicated Playlists & Favorites collections',
                    );
                  },
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined, color: PulseColors.primaryMint),
                  title: const Text('Clear Temporary Cache', style: TextStyle(color: PulseColors.textWhite, fontSize: 14)),
                  subtitle: const Text('Frees space without deleting your songs', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await StorageService.instance.clearTempCache();
                    await _loadPreferences();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Temporary cache cleared. All songs are safe.'),
                        backgroundColor: PulseColors.primaryMint,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Bottom clean watermark
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover),
                ),
                const SizedBox(height: 6),
                const Text(
                  'CHITAURI AUDIO SUITE',
                  style: TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Simple • Fast • Free',
                  style: TextStyle(color: PulseColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
