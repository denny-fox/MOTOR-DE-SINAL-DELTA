import '../models/match_record.dart';
import '../forecast_engine.dart';

class BacktestRow {
  const BacktestRow({
    required this.match,
    required this.raw,
    required this.calibrated,
    required this.rawBrier,
    required this.calibratedBrier,
  });

  final MatchRecord match;
  final Forecast raw;
  final Forecast calibrated;
  final double rawBrier;
  final double calibratedBrier;
}

class CalibrationBin {
  const CalibrationBin({
    required this.outcome,
    required this.lowerBound,
    required this.upperBound,
    required this.meanProbability,
    required this.observedRate,
    required this.count,
  });

  final String outcome;
  final double lowerBound;
  final double upperBound;
  final double meanProbability;
  final double observedRate;
  final int count;
}

class BacktestReport {
  const BacktestReport({
    required this.rows,
    required this.rawBrier,
    required this.calibratedBrier,
    required this.calibrationBins,
    required this.accuracy,
  });

  final List<BacktestRow> rows;
  final double rawBrier;
  final double calibratedBrier;
  final List<CalibrationBin> calibrationBins;
  final double accuracy;
}

class WalkForwardBacktest {
  static BacktestReport run(Iterable<MatchRecord> matches) {
    final completed = matches
        .where((match) => match.hasResult)
        .map((match) => (match: match, kickoff: DateTime.parse(match.kickoff)))
        .toList()
      ..sort((a, b) {
        final dateOrder = a.kickoff.compareTo(b.kickoff);
        return dateOrder != 0
            ? dateOrder
            : (a.match.id ?? 0).compareTo(b.match.id ?? 0);
      });

    final rows = <BacktestRow>[];
    final predictedSums = [0.0, 0.0, 0.0];
    final observedCounts = [0, 0, 0];

    var batchStart = 0;
    while (batchStart < completed.length) {
      var batchEnd = batchStart + 1;
      final kickoff = completed[batchStart].kickoff;
      while (batchEnd < completed.length &&
          completed[batchEnd].kickoff.isAtSameMomentAs(kickoff)) {
        batchEnd++;
      }

      final batchProbabilities = <List<double>>[];
      final batchOutcomes = <int>[];
      for (var matchIndex = batchStart; matchIndex < batchEnd; matchIndex++) {
        final entry = completed[matchIndex];
        final match = entry.match;
        final raw = ForecastEngine.calculate(
          homeExpectedGoals: match.homeXg,
          awayExpectedGoals: match.awayXg,
        );
        final rawProbabilities = [raw.homeWin, raw.draw, raw.awayWin];
        final observed = _outcome(match);
        final calibratedProbabilities =
            _calibrate(rawProbabilities, predictedSums, observedCounts);
        final calibrated = Forecast(
          homeWin: calibratedProbabilities[0],
          draw: calibratedProbabilities[1],
          awayWin: calibratedProbabilities[2],
          overTwoFive: raw.overTwoFive,
          bothTeamsToScore: raw.bothTeamsToScore,
        );

        rows.add(BacktestRow(
          match: match,
          raw: raw,
          calibrated: calibrated,
          rawBrier: _brier(rawProbabilities, observed),
          calibratedBrier: _brier(calibratedProbabilities, observed),
        ));
        batchProbabilities.add(rawProbabilities);
        batchOutcomes.add(observed);
      }

      for (var index = 0; index < batchProbabilities.length; index++) {
        for (var outcome = 0; outcome < 3; outcome++) {
          predictedSums[outcome] += batchProbabilities[index][outcome];
        }
        observedCounts[batchOutcomes[index]]++;
      }
      batchStart = batchEnd;
    }

    if (rows.isEmpty) {
      return const BacktestReport(
        rows: [],
        rawBrier: 0,
        calibratedBrier: 0,
        calibrationBins: [],
        accuracy: 0,
      );
    }

    return BacktestReport(
      rows: rows,
      rawBrier:
          rows.map((row) => row.rawBrier).reduce((a, b) => a + b) / rows.length,
      calibratedBrier:
          rows.map((row) => row.calibratedBrier).reduce((a, b) => a + b) /
              rows.length,
      calibrationBins: _calibrationBins(rows),
      accuracy: rows
              .where((row) =>
                  _argMax([row.raw.homeWin, row.raw.draw, row.raw.awayWin]) ==
                  _outcome(row.match))
              .length /
          rows.length,
    );
  }

  static List<double> _calibrate(
      List<double> raw, List<double> predictedSums, List<int> observedCounts) {
    final historicalCount = observedCounts.reduce((a, b) => a + b);
    if (historicalCount == 0) return raw;

    final adjusted = List.generate(3, (index) {
      final observedRate = (observedCounts[index] + 1) / (historicalCount + 3);
      final predictedRate = (predictedSums[index] + 1) / (historicalCount + 3);
      return raw[index] * observedRate / predictedRate;
    });
    final total = adjusted.reduce((a, b) => a + b);
    return adjusted.map((probability) => probability / total).toList();
  }

  static int _outcome(MatchRecord match) {
    if (match.homeScore! > match.awayScore!) return 0;
    if (match.homeScore! == match.awayScore!) return 1;
    return 2;
  }

  static double _brier(List<double> probabilities, int observed) =>
      List.generate(
              3,
              (index) => mathSquare(
                  probabilities[index] - (index == observed ? 1 : 0)))
          .reduce((a, b) => a + b) /
      3;

  static double mathSquare(double value) => value * value;

  static int _argMax(List<double> values) {
    var best = 0;
    for (var index = 1; index < values.length; index++) {
      if (values[index] > values[best]) best = index;
    }
    return best;
  }

  static List<CalibrationBin> _calibrationBins(List<BacktestRow> rows) {
    const labels = ['Casa', 'Empate', 'Visitante'];
    final counts = List.filled(30, 0);
    final probabilitySums = List.filled(30, 0.0);
    final observedCounts = List.filled(30, 0);

    for (final row in rows) {
      final probabilities = [row.raw.homeWin, row.raw.draw, row.raw.awayWin];
      final observed = _outcome(row.match);
      for (var outcome = 0; outcome < 3; outcome++) {
        final bucket =
            (probabilities[outcome] * 10).floor().clamp(0, 9).toInt();
        final index = outcome * 10 + bucket;
        counts[index]++;
        probabilitySums[index] += probabilities[outcome];
        if (observed == outcome) observedCounts[index]++;
      }
    }

    final bins = <CalibrationBin>[];
    for (var outcome = 0; outcome < 3; outcome++) {
      for (var bucket = 0; bucket < 10; bucket++) {
        final lower = bucket / 10;
        final upper = (bucket + 1) / 10;
        final index = outcome * 10 + bucket;
        if (counts[index] == 0) continue;
        bins.add(CalibrationBin(
          outcome: labels[outcome],
          lowerBound: lower,
          upperBound: upper,
          meanProbability: probabilitySums[index] / counts[index],
          observedRate: observedCounts[index] / counts[index],
          count: counts[index],
        ));
      }
    }
    return bins;
  }
}
