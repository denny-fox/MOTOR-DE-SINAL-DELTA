import 'package:flutter_test/flutter_test.dart';
import 'package:delta_signal_engine/data/match_importer.dart';

void main() {
  group('MatchImporter', () {
    test('parses CSV headers and quoted team names', () {
      final matches = MatchImporter.parse(
        'competition,home_team,away_team,home_xg,away_xg,kickoff,home_score,away_score\n'
        'Liga,"Time, da Casa",Visitante,1.5,0.8,2026-04-01,2,0',
        extension: 'csv',
      );

      expect(matches, hasLength(1));
      expect(matches.single.homeTeam, 'Time, da Casa');
      expect(matches.single.homeScore, 2);
    });

    test('parses CSV files with a UTF-8 BOM', () {
      final matches = MatchImporter.parse(
        '\uFEFFcompetition,home_team,away_team,home_xg,away_xg,kickoff,home_score,away_score\n'
        'Liga,Casa,Fora,1.2,0.8,2026-04-01,,',
        extension: 'csv',
      );

      expect(matches.single.hasResult, isFalse);
    });

    test('parses CSV files with Windows line endings', () {
      final matches = MatchImporter.parse(
        'competition,home_team,away_team,home_xg,away_xg,kickoff,home_score,away_score\r\n'
        'Liga,Casa,Fora,1.2,0.8,2026-04-01,1,0',
        extension: 'csv',
      );

      expect(matches.single.homeScore, 1);
    });

    test('rejects duplicate CSV headers', () {
      expect(
        () => MatchImporter.parse(
          'competition,home_team,away_team,home_xg,away_xg,kickoff,home_score,home_score\n'
          'Liga,Casa,Fora,1.2,0.8,2026-04-01,1,2',
          extension: 'csv',
        ),
        throwsFormatException,
      );
    });

    test('parses JSON matches and allows upcoming games without scores', () {
      final matches = MatchImporter.parse(
        '[{"competition":"Liga","home_team":"Casa","away_team":"Fora",'
        '"home_xg":1.3,"away_xg":0.9,"kickoff":"2026-04-01"}]',
        extension: 'json',
      );

      expect(matches.single.hasResult, isFalse);
      expect(matches.single.homeXg, 1.3);
    });

    test('rejects simulated competitions', () {
      expect(
        () => MatchImporter.parse(
          '[{"competition":"Liga SRL","home_team":"Casa","away_team":"Fora",'
          '"home_xg":1,"away_xg":1,"kickoff":"2026-04-01"}]',
          extension: 'json',
        ),
        throwsFormatException,
      );
    });

    test(
        'rejects incomplete scores and expected goals outside the supported range',
        () {
      expect(
        () => MatchImporter.parse(
          '[{"competition":"Liga","home_team":"Casa","away_team":"Fora",'
          '"home_xg":1,"away_xg":1,"kickoff":"2026-04-01","home_score":2}]',
          extension: 'json',
        ),
        throwsFormatException,
      );
      expect(
        () => MatchImporter.parse(
          '[{"competition":"Liga","home_team":"Casa","away_team":"Fora",'
          '"home_xg":11,"away_xg":1,"kickoff":"2026-04-01"}]',
          extension: 'json',
        ),
        throwsFormatException,
      );
    });
  });
}
