import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/widgets/trust_score.dart';

void main() {
  group('TrustScore Tiering Tests', () {
    test('returns notEnoughData when ratingCount < 3', () {
      const score0 = TrustScore(ratingAverage: null, ratingCount: 0);
      expect(score0.tier, ScoreTier.notEnoughData);

      const score2 = TrustScore(ratingAverage: 5.0, ratingCount: 2);
      expect(score2.tier, ScoreTier.notEnoughData);
    });

    test('returns green when score >= 80 and ratingCount >= 3', () {
      const score = TrustScore(ratingAverage: 4.5, ratingCount: 3); // 90 / 100
      expect(score.scoreOutOf100, 90.0);
      expect(score.tier, ScoreTier.green);
    });

    test('returns yellow when score is 50..79 and ratingCount >= 3', () {
      const score = TrustScore(ratingAverage: 3.5, ratingCount: 4); // 70 / 100
      expect(score.scoreOutOf100, 70.0);
      expect(score.tier, ScoreTier.yellow);
    });

    test('requires minReviewsToShowRed (5) before surfacing red tier', () {
      // Score < 50 with only 3 or 4 reviews -> notEnoughData (hostile review guard)
      const score3 = TrustScore(ratingAverage: 2.0, ratingCount: 3); // 40 / 100
      expect(score3.tier, ScoreTier.notEnoughData);

      const score4 = TrustScore(ratingAverage: 2.0, ratingCount: 4); // 40 / 100
      expect(score4.tier, ScoreTier.notEnoughData);

      // Score < 50 with 5 reviews -> red tier
      const score5 = TrustScore(ratingAverage: 2.0, ratingCount: 5); // 40 / 100
      expect(score5.tier, ScoreTier.red);
    });
  });
}
