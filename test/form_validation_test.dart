import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delta_signal_engine/main.dart';
import 'package:delta_signal_engine/models/match_record.dart';

void main() {
  testWidgets(
      'result dialog shows validation errors instead of silently ignoring invalid scores',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<(int, int)>(
              context: context,
              builder: (_) => const ResultDialog(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Use inteiro >= 0'), findsNWidgets(2));

    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('result dialog preloads and returns the corrected score',
      (tester) async {
    (int, int)? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<(int, int)>(
                context: context,
                builder: (_) => const ResultDialog(
                  initialHomeScore: 1,
                  initialAwayScore: 0,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        '1');
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        '0');

    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(result, (2, 1));
  });

  testWidgets('new match form validates and saves the manual forecast',
      (tester) async {
    MatchRecord? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showModalBottomSheet<MatchRecord>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AddMatchSheet(),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Liga');
    await tester.enterText(find.byType(TextFormField).at(2), 'Casa');
    await tester.enterText(find.byType(TextFormField).at(3), 'Visitante');
    await tester.tap(find.text('Calcular e salvar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.competition, 'Liga');
    expect(result!.homeTeam, 'Casa');
    expect(result!.awayTeam, 'Visitante');
    expect(result!.homeXg, 1.4);
    expect(result!.awayXg, 1.1);
  });
}
