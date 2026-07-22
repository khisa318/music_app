import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0A1A),
        body: Stack(
          children: [
            // Ambient Background Glow
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF9D4EDD).withValues(alpha: 0.25),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9D4EDD).withValues(alpha: 0.25),
                      blurRadius: 120,
                      spreadRadius: 50,
                    ),
                  ],
                ),
              ),
            ),

            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Bar / Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.help_outline_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Compact Profile Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.08),
                            Colors.white.withValues(alpha: 0.03),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 26,
                            backgroundImage: NetworkImage(
                              'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Armstrong Khisa',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'khisaarmstrong@gmail.com',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9D4EDD),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'PREMIUM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Settings Section Tabs
                  const TabBar(
                    indicatorColor: Color(0xFF9D4EDD),
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    tabs: [
                      Tab(text: 'Playback'),
                      Tab(text: 'Storage & Data'),
                      Tab(text: 'Account'),
                    ],
                  ),

                  // Tab Views
                  const Expanded(
                    child: TabBarView(
                      children: [_PlaybackTab(), _StorageTab(), _AccountTab()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TAB 1: PLAYBACK ---
class _PlaybackTab extends StatefulWidget {
  const _PlaybackTab();

  @override
  State<_PlaybackTab> createState() => _PlaybackTabState();
}

class _PlaybackTabState extends State<_PlaybackTab> {
  bool _offlineMode = false;
  bool _normalizeVolume = true;
  bool _explicitContent = true;
  String _streamQuality = 'High (320 kbps)';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSwitchCard(
          title: 'Offline Mode',
          subtitle: 'Only play downloaded tracks when network is unavailable',
          value: _offlineMode,
          onChanged: (v) => setState(() => _offlineMode = v),
        ),
        _buildSelectionCard(
          title: 'Streaming Quality',
          currentValue: _streamQuality,
          options: [
            'Low (96 kbps)',
            'Normal (160 kbps)',
            'High (320 kbps)',
            'Very High (Lossless)',
          ],
          onSelected: (val) => setState(() => _streamQuality = val),
        ),
        _buildSwitchCard(
          title: 'Normalize Volume',
          subtitle: 'Set the same audio level for all tracks',
          value: _normalizeVolume,
          onChanged: (v) => setState(() => _normalizeVolume = v),
        ),
        _buildSwitchCard(
          title: 'Allow Explicit Content',
          subtitle: 'Turn off to skip explicit tracks automatically',
          value: _explicitContent,
          onChanged: (v) => setState(() => _explicitContent = v),
        ),
        _buildActionCard(
          title: 'Equalizer',
          subtitle: 'Adjust bass, treble, and vocal acoustics',
          icon: Icons.equalizer_rounded,
          onTap: () {},
        ),
      ],
    );
  }
}

// --- TAB 2: STORAGE ---
class _StorageTab extends StatefulWidget {
  const _StorageTab();

  @override
  State<_StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<_StorageTab> {
  bool _downloadOnWifiOnly = true;
  String _downloadQuality = 'Very High (Lossless)';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Device Storage',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '14.2 GB Used',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: 0.35,
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF9D4EDD),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  _StorageLegend(
                    color: Color(0xFF9D4EDD),
                    label: 'Downloads (4.2 GB)',
                  ),
                  SizedBox(width: 16),
                  _StorageLegend(
                    color: Colors.white38,
                    label: 'Cache (1.1 GB)',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSwitchCard(
          title: 'Download over Wi-Fi Only',
          subtitle: 'Save cellular data during background downloads',
          value: _downloadOnWifiOnly,
          onChanged: (v) => setState(() => _downloadOnWifiOnly = v),
        ),
        _buildSelectionCard(
          title: 'Download Quality',
          currentValue: _downloadQuality,
          options: [
            'Normal (160 kbps)',
            'High (320 kbps)',
            'Very High (Lossless)',
          ],
          onSelected: (val) => setState(() => _downloadQuality = val),
        ),
        _buildActionCard(
          title: 'Clear Cache',
          subtitle: 'Free up 1.1 GB. Downloaded songs won\'t be deleted',
          icon: Icons.cleaning_services_rounded,
          onTap: () {},
        ),
      ],
    );
  }
}

// --- TAB 3: ACCOUNT ---
class _AccountTab extends StatefulWidget {
  const _AccountTab();

  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  bool _pushNotifications = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSwitchCard(
          title: 'Push Notifications',
          subtitle: 'Get alerts for new releases from artists you follow',
          value: _pushNotifications,
          onChanged: (v) => setState(() => _pushNotifications = v),
        ),
        _buildActionCard(
          title: 'Connected Devices',
          subtitle: 'Manage active speakers and Bluetooth sessions',
          icon: Icons.devices_rounded,
          onTap: () {},
        ),
        _buildActionCard(
          title: 'Privacy & Data Sharing',
          subtitle: 'Control listening history visibility',
          icon: Icons.lock_outline_rounded,
          onTap: () {},
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.redAccent,
              size: 18,
            ),
            label: const Text(
              'Log Out',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {},
          ),
        ),
      ],
    );
  }
}

// --- HELPER CARD BUILDERS ---
Widget _buildSwitchCard({
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeTrackColor: const Color(0xFF9D4EDD),
          activeThumbColor: Colors.white,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

Widget _buildSelectionCard({
  required String title,
  required String currentValue,
  required List<String> options,
  required ValueChanged<String> onSelected,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: currentValue,
          dropdownColor: const Color(0xFF1E1430),
          style: const TextStyle(
            color: Color(0xFF9D4EDD),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          items: options.map((opt) {
            return DropdownMenuItem(value: opt, child: Text(opt));
          }).toList(),
          onChanged: (val) {
            if (val != null) onSelected(val);
          },
        ),
      ],
    ),
  );
}

Widget _buildActionCard({
  required String title,
  required String subtitle,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    ),
  );
}

class _StorageLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _StorageLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}
