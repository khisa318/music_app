import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/home/data/providers/personalized_recommendation_provider.dart';

void main() {
  group('PersonalizedRecommendationProvider.calculateArtistAffinities', () {
    test('recent listening can overtake a long-term favourite', () {
      final scores =
          PersonalizedRecommendationProvider.calculateArtistAffinities(
            // Years of an old favourite vs. a short recent session.
            lifetimeSeconds: {'Old Favourite': 100000, 'New Artist': 600},
            recentSeconds: {'New Artist': 600},
          );

      expect(scores['New Artist'], greaterThan(scores['Old Favourite']!));
      expect(scores['New Artist'], 1.0);
    });

    test('keeps lifetime favourites in the ranking for a second mix', () {
      final scores =
          PersonalizedRecommendationProvider.calculateArtistAffinities(
            lifetimeSeconds: {'Old Favourite': 100000, 'New Artist': 600},
            recentSeconds: {'New Artist': 600},
          );

      // The old favourite must still be present (and near the top) so the
      // listener keeps both a familiar mix and a mix for the new taste.
      expect(scores.keys, contains('Old Favourite'));
      expect(scores.length, 2);
      expect(scores['Old Favourite'], greaterThan(0.0));
    });

    test('recent-heavy listening stays on top when both artists are heard', () {
      final scores =
          PersonalizedRecommendationProvider.calculateArtistAffinities(
            lifetimeSeconds: {'Hip Hop': 20000, 'Afrobeats': 1000},
            recentSeconds: {'Hip Hop': 300, 'Afrobeats': 1800},
          );

      expect(scores['Afrobeats'], greaterThan(scores['Hip Hop']!));
    });

    test('falls back to lifetime data when no recent window exists', () {
      final scores =
          PersonalizedRecommendationProvider.calculateArtistAffinities(
            lifetimeSeconds: {'A': 900, 'B': 100},
            recentSeconds: const {},
          );

      expect(scores['A'], 1.0);
      expect(scores['B'], closeTo(1 / 9, 0.0001));
    });

    test('returns an empty map for empty inputs', () {
      final scores =
          PersonalizedRecommendationProvider.calculateArtistAffinities(
            lifetimeSeconds: const {},
            recentSeconds: const {},
          );

      expect(scores, isEmpty);
    });
  });
}
