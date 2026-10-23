import 'package:flutter_test/flutter_test.dart';
import 'package:delta_signal_engine/forecast_engine.dart';

void main() {
  group('ForecastEngine', () {
    test('normalizes 1X2 probabilities', () {
      final forecast = ForecastEngine.calculate(
        homeExpectedGoals: 1.4,
        awayExpectedGoals: 1.1,
      );

      expect(forecast.homeWin + forecast.draw + forecast.awayWin, closeTo(1, 1e-10));
      expect(forecast.overTwoFive, inInclusiveRange(0, 1));
      expect(forecast.bothTeamsToScore, inInclusiveRange(0, 1));
    });

    test('equal expected goals produce symmetric win probabilities', () {
      final forecast = ForecastEngine.calculate(
        homeExpectedGoals: 1.2,
        awayExpectedGoals: 1.2,
      );

      expect(forecast.homeWin, closeTo(forecast.awayWin, 1e-10));
    });

    test('retains Poisson probability mass for expected goals near the maximum', () {
      final forecast = ForecastEngine.calculate(
        homeExpectedGoals: 10,
        awayExpectedGoals: 10,
      );

      expect(forecast.homeWin + forecast.draw + forecast.awayWin, closeTo(1, 1e-10));
      expect(forecast.overTwoFive, greaterThan(0.99));
      expect(forecast.bothTeamsToScore, greaterThan(0.99));
      expect(forecast.homeWin, closeTo(forecast.awayWin, 1e-10));
    });

    test('rejects expected goals outside the supported range', () {
      expect(
        () => ForecastEngine.calculate(homeExpectedGoals: double.nan, awayExpectedGoals: 1),
        throwsArgumentError,
      );
      expect(
        () => ForecastEngine.calculate(homeExpectedGoals: 1, awayExpectedGoals: 10.1),
        throwsArgumentError,
      );
    });

    test('activates a signal only at its configured threshold', () {
      const signal = ForecastSignal('T01', 'Home', 0.52, 0.52);

      expect(signal.isActive, isTrue);
      expect(const ForecastSignal('T01', 'Home', 0.519, 0.52).isActive, isFalse);
    });
  });
}
