import 'package:flutter_test/flutter_test.dart';
import 'package:delta_signal_engine/analysis/walk_forward_backtest.dart';
import 'package:delta_signal_engine/models/match_record.dart';

MatchRecord match(
        {required String date, required int home, required int away}) =>
    MatchRecord(
      competition: 'Liga',
      homeTeam: 'Casa',
      awayTeam: 'Fora',
      homeXg: 1.4,
      awayXg: 1.0,
      kickoff: date,
      homeScore: home,
      awayScore: away,
    );

void main() {
  group('WalkForwardBacktest', () {
    test(
        'orders completed matches chronologically and excludes unfinished games',
        () {
      final report = WalkForwardBacktest.run([
        match(date: '2026-03-03', home: 0, away: 1),
        match(date: '2026-03-01', home: 1, away: 0),
        MatchRecord(
          competition: 'Liga',
          homeTeam: 'A',
          awayTeam: 'B',
          homeXg: 1,
          awayXg: 1,
          kickoff: '2026-03-02',
        ),
      ]);

      expect(report.rows, hasLength(2));
      expect(report.rows.first.match.kickoff, startsWith('2026-03-01'));
      expect(report.rows.last.match.kickoff, startsWith('2026-03-03'));
    });

    test('does not use the current result when calibrating its forecast', () {
      final report = WalkForwardBacktest.run([
        match(date: '2026-03-01', home: 1, away: 0),
        match(date: '2026-03-02', home: 1, away: 0),
      ]);

      expect(
          report.rows.first.calibrated.homeWin, report.rows.first.raw.homeWin);
      expect(report.rows.last.calibrated.homeWin,
          isNot(report.rows.last.raw.homeWin));
      expect(report.rawBrier, inInclusiveRange(0, 1));
      expect(report.calibrationBins, isNotEmpty);
    });

    test('does not use results from matches at the same kickoff time', () {
      final first = match(date: '2026-03-01T12:00:00Z', home: 1, away: 0);
      final second = match(date: '2026-03-01T12:00:00+00:00', home: 0, away: 1);
      final later = match(date: '2026-03-02T12:00:00Z', home: 1, away: 0);

      final report = WalkForwardBacktest.run([first, second, later]);

      expect(report.rows[0].calibrated.homeWin, report.rows[0].raw.homeWin);
      expect(report.rows[1].calibrated.homeWin, report.rows[1].raw.homeWin);
      expect(
          report.rows[2].calibrated.homeWin, isNot(report.rows[2].raw.homeWin));
    });

    test(
        'calibration bins account for all three outcomes of every completed match',
        () {
      final report = WalkForwardBacktest.run([
        match(date: '2026-03-01', home: 1, away: 0),
        match(date: '2026-03-02', home: 0, away: 0),
        match(date: '2026-03-03', home: 0, away: 1),
      ]);

      expect(
        report.calibrationBins.fold<int>(0, (total, bin) => total + bin.count),
        report.rows.length * 3,
      );
    });
  });
}
