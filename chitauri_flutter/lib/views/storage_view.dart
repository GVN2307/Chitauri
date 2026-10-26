import 'dart:io';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/pulse_theme.dart';

class StorageView extends StatefulWidget {
  const StorageView({super.key});

  @override
  State<StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<StorageView> {
  bool _isNomediaActive = false;
  String _folderPath = '';
  List<FileSystemEntity> _files = [];
  int _totalBytes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  Future<void> _loadStorageData() async {
    setState(() {
      _isLoading = true;
    });

    final storage = StorageService.instance;
    final dir = await storage.getMusicDir();
    final isNomedia = await storage.isNomediaActive();
    final files = await storage.listFiles();
    final bytes = await storage.getTotalDiskUsedBytes();

    if (mounted) {
      setState(() {
        _folderPath = dir.path;
        _isNomediaActive = isNomedia;
        _files = files;
        _totalBytes = bytes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: PulseColors.primaryMint));
    }

    final mbUsed = (_totalBytes / (1024 * 1024)).toStringAsFixed(2);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.security, color: PulseColors.primaryMint, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'PRIVATE OFFLINE VAULT',
                      style: TextStyle(color: PulseColors.primaryMint, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: PulseColors.onPrimaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PulseColors.primaryMint, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: PulseColors.primaryMint, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _isNomediaActive
                            ? 'PRIVACY ACTIVE: Hidden from Other Music Players'
                            : 'PRIVACY INACTIVE: Sentinel Missing',
                        style: const TextStyle(color: PulseColors.primaryMint, fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your downloaded audio is stored in a private directory guarded by Android\'s \'.nomedia\' sentinel. This keeps your tracks hidden from external media scanners (Spotify, VLC, Apple Music), while remaining directly accessible in your device\'s File Manager.',
                  style: TextStyle(color: PulseColors.onSurfaceVariant, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Directory Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DIRECTORY DETAILS',
                  style: TextStyle(color: PulseColors.textMuted, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                const Text(
                  'App Storage Path:',
                  style: TextStyle(color: PulseColors.textWhite, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PulseColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _folderPath,
                    style: const TextStyle(color: PulseColors.primaryMint, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem('TOTAL FILES', '${_files.length}', PulseColors.textWhite),
                    _buildStatItem('DISK USED', '$mbUsed MB', PulseColors.primaryMint),
                    _buildStatItem('SENTINEL', _isNomediaActive ? '.nomedia OK' : 'MISSING', PulseColors.primaryMint),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () async {
                    await StorageService.instance.ensureNomedia();
                    await _loadStorageData();
                  },
                  icon: const Icon(Icons.sync, size: 16, color: PulseColors.onPrimary),
                  label: const Text('Re-verify .nomedia Shield', style: TextStyle(color: PulseColors.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PulseColors.primaryMint,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Physical Files on Disk
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PHYSICAL FILES ON DISK',
                  style: TextStyle(color: PulseColors.textMuted, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.6),
                ),
                const SizedBox(height: 10),
                if (_files.isEmpty)
                  const Text('No files in music directory.', style: TextStyle(color: PulseColors.textMuted, fontSize: 12))
                else
                  ..._files.map((file) {
                    final name = file.path.split(Platform.pathSeparator).last;
                    final isShield = name == '.nomedia';
                    final isMp3 = name.endsWith('.mp3');

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            isShield
                                ? Icons.shield
                                : isMp3
                                    ? Icons.audiotrack
                                    : Icons.description,
                            color: isShield
                                ? PulseColors.primaryMint
                                : isMp3
                                    ? PulseColors.primaryMint
                                    : PulseColors.textMuted,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isShield ? PulseColors.primaryMint : PulseColors.textWhite,
                                fontSize: 12,
                                fontWeight: isShield ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: PulseColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
