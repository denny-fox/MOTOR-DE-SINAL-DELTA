import 'dart:math' as math;

class Forecast {
  const Forecast({
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.overTwoFive,
    required this.bothTeamsToScore,
  });

  final double homeWin;
  final double draw;
  final double awayWin;
  final double overTwoFive;
  final double bothTeamsToScore;

  List<ForecastSignal> get signals => [
        ForecastSignal('T01', 'Vitoria da casa', homeWin, 0.52),
        ForecastSignal('T02', 'Empate', draw, 0.30),
        ForecastSignal('T03', 'Mais de 2,5 gols', overTwoFive, 0.55),
        ForecastSignal('T04', 'Ambas marcam', bothTeamsToScore, 0.55),
        ForecastSignal('T05', 'Vitoria visitante', awayWin, 0.40),
      ];
}

class ForecastSignal {
  const ForecastSignal(this.code, this.label, this.probability, this.threshold);

  final String code;
  final String label;
  final double probability;
  final double threshold;

  bool get isActive => probability >= threshold;
}

class ForecastEngine {
  static const _maximumExpectedGoals = 10.0;
  static const _poissonTailTolerance = 1e-12;

  static Forecast calculate({
    required double homeExpectedGoals,
    required double awayExpectedGoals,
  }) {
    _validateExpectedGoals('homeExpectedGoals', homeExpectedGoals);
    _validateExpectedGoals('awayExpectedGoals', awayExpectedGoals);
    final homeScores = _poisson(homeExpectedGoals);
    final awayScores = _poisson(awayExpectedGoals);
    var homeWin = 0.0;
    var draw = 0.0;
    var awayWin = 0.0;
    var overTwoFive = 0.0;
    var bothTeamsToScore = 0.0;
    var total = 0.0;

    for (var home = 0; home < homeScores.length; home++) {
      for (var away = 0; away < awayScores.length; away++) {
        final probability = homeScores[home] * awayScores[away];
        total += probability;
        if (home > away) homeWin += probability;
        if (home == away) draw += probability;
        if (home < away) awayWin += probability;
        if (home + away > 2) overTwoFive += probability;
        if (home > 0 && away > 0) bothTeamsToScore += probability;
      }
    }

    return Forecast(
      homeWin: homeWin / total,
      draw: draw / total,
      awayWin: awayWin / total,
      overTwoFive: overTwoFive / total,
      bothTeamsToScore: bothTeamsToScore / total,
    );
  }

  static List<double> _poisson(double expectedGoals) {
    final probabilities = <double>[];
    var probability = math.exp(-expectedGoals);
    var cumulative = probability;
    probabilities.add(probability);
    for (var goals = 1; cumulative < 1 - _poissonTailTolerance; goals++) {
      probability *= expectedGoals / goals;
      probabilities.add(probability);
      cumulative += probability;
    }
    return probabilities;
  }

  static void _validateExpectedGoals(String name, double value) {
    if (!value.isFinite || value < 0 || value > _maximumExpectedGoals) {
      throw ArgumentError.value(value, name, 'must be finite and between 0 and 10');
    }
  }
}
