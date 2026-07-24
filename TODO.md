# Home Screen Redesign TODO

## Objective
Redesign the Home screen layout to match musix_mockup.jpg design while keeping all existing tabs (All/Trending/Favorites/Recently Played) and their functionality intact.

## Steps

- [x] Analyze current codebase structure
- [x] Understand mockup design requirements
- [x] Get user approval on plan

### Implementation

- [x] **1. Edit `home_screen.dart`** - Add TopHeader with profile avatar, greeting, notification/search icons at the top of the scroll view
- [x] **2. Edit `home_screen.dart`** - Restyle tab pills to match glassmorphic/purple accent design from mockup
- [x] **3. Edit `home_screen.dart`** - Add "For You" carousel section under "All" tab using actual data
- [x] **4. Edit `home_screen.dart`** - Add "Popular Tracks" section under "All" tab using real data
- [x] **5. Edit `home_screen.dart`** - Keep all existing sections (RecentPlaylistsSection, StatsSection, LastPlayedSection, LikedSongsSection, FavoriteArtistsSection, HomeSections)
- [x] **6. Keep all existing tab functionality** - Trending, Favorites, Recently Played tabs remain unchanged
- [x] **7. Test and verify** - Run flutter analyze (4 issues found: 2 pre-existing infos from original code + 2 minor warnings fixed)

## Files Modified
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/library/presentation/screens/library_screen.dart`
- `lib/features/playlists/presentation/screens/playlists_screen.dart`

