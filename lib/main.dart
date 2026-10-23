import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'analysis/walk_forward_backtest.dart';
import 'data/match_importer.dart';
import 'forecast_engine.dart';
import 'models/match_record.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeltaSignalApp());
}

class DeltaSignalApp extends StatelessWidget {
  const DeltaSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF182421);
    return MaterialApp(
      title: 'Delta Signal Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F0),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16785B),
          primary: const Color(0xFF16785B),
          onPrimary: Colors.white,
          surface: const Color(0xFFFFFFFF),
          onSurface: ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F5F0),
          foregroundColor: ink,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class MatchStore {
  MatchStore._();
  static final MatchStore instance = MatchStore._();
  Future<Database>? _databaseFuture;

  Future<Database> get database async {
    final existing = _databaseFuture;
    if (existing != null) return existing;
    final opening = _openDatabase();
    _databaseFuture = opening;
    try {
      return await opening;
    } catch (_) {
      if (identical(_databaseFuture, opening)) _databaseFuture = null;
      rethrow;
    }
  }

  Future<Database> _openDatabase() async {
    final databasePath = path.join(await getDatabasesPath(), 'delta_signal.db');
    return openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE matches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            competition TEXT NOT NULL,
            home_team TEXT NOT NULL,
            away_team TEXT NOT NULL,
            home_xg REAL NOT NULL,
            away_xg REAL NOT NULL,
            kickoff TEXT NOT NULL,
            home_score INTEGER,
            away_score INTEGER
          )
        ''');
      },
    );
  }

  Future<List<MatchRecord>> all() async {
    final rows = await (await database).query(
      'matches',
      orderBy: 'kickoff DESC, id DESC',
    );
    return rows.map(MatchRecord.fromMap).toList();
  }

  Future<void> add(MatchRecord match) async {
    final values = match.toMap()..remove('id');
    await (await database).insert('matches', values);
  }

  Future<int> importAll(List<MatchRecord> matches) async {
    final db = await database;
    return db.transaction((transaction) async {
      var inserted = 0;
      for (final match in matches) {
        final existing = await transaction.query(
          'matches',
          columns: ['id'],
          where:
              'competition = ? AND home_team = ? AND away_team = ? AND kickoff = ?',
          whereArgs: [
            match.competition,
            match.homeTeam,
            match.awayTeam,
            match.kickoff
          ],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final values = match.toMap()..remove('id');
        await transaction.insert('matches', values);
        inserted++;
      }
      return inserted;
    });
  }

  Future<void> setResult(int id, int homeScore, int awayScore) async {
    await (await database).update(
      'matches',
      {'home_score': homeScore, 'away_score': awayScore},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;
  List<MatchRecord> _matches = [];
  BacktestReport? _backtestReport;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final matches = await MatchStore.instance.all();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _backtestReport = null;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Falha ao carregar os jogos: $error';
        _loading = false;
      });
    }
  }

  Future<void> _addMatch() async {
    final match = await showModalBottomSheet<MatchRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddMatchSheet(),
    );
    if (match == null) return;
    final normalizedLeague = match.competition.toLowerCase();
    if (normalizedLeague.contains('srl') ||
        normalizedLeague.contains('simulad')) {
      _message('Jogos SRL ou simulados nao sao aceitos.');
      return;
    }
    try {
      await MatchStore.instance.add(match);
      await _refresh();
    } catch (error) {
      _message('Falha ao guardar o jogo: $error');
    }
  }

  Future<void> _importMatches() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final extension = file.extension ?? file.name.split('.').last;
      final records =
          MatchImporter.parse(utf8.decode(bytes), extension: extension);
      final inserted = await MatchStore.instance.importAll(records);
      await _refresh();
      if (mounted) {
        _message(
            '${records.length} partidas lidas; $inserted novas e ${records.length - inserted} ja existentes.');
      }
    } on FormatException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Falha ao importar arquivo: $error');
    }
  }

  Future<void> _recordResult(MatchRecord match) async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (_) => ResultDialog(
        initialHomeScore: match.homeScore,
        initialAwayScore: match.awayScore,
      ),
    );
    if (result == null || match.id == null) return;
    try {
      await MatchStore.instance.setResult(match.id!, result.$1, result.$2);
      await _refresh();
    } catch (error) {
      _message('Falha ao guardar o resultado: $error');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final completed = _matches.where((match) => match.hasResult).length;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.insights, color: Color(0xFF16785B), size: 23),
            SizedBox(width: 9),
            Text('DELTA SIGNAL',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Importar CSV ou JSON',
            onPressed: _importMatches,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: 'Adicionar jogo',
            onPressed: _addMatch,
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 12),
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            setState(() => _loading = true);
                            await _refresh();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  top: false,
                  child: _tab == 2
                      ? _signalsView()
                      : _tab == 3
                          ? _validationView()
                          : _tab == 1
                              ? _matchesView(_matches)
                              : _dashboardView(completed),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMatch,
        icon: const Icon(Icons.add),
        label: const Text('Novo jogo'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Painel'),
          NavigationDestination(
              icon: Icon(Icons.sports_soccer), label: 'Jogos'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Sinais'),
          NavigationDestination(
              icon: Icon(Icons.query_stats), label: 'Validacao'),
        ],
      ),
    );
  }

  Widget _dashboardView(int completed) {
    final upcoming = _matches.where((match) => !match.hasResult).toList();
    final activeSignals = upcoming
        .expand((match) => ForecastEngine.calculate(
              homeExpectedGoals: match.homeXg,
              awayExpectedGoals: match.awayXg,
            ).signals)
        .where((signal) => signal.isActive)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        Text('ANALISE LOCAL  /  MODELO POISSON', style: _eyebrowStyle),
        const SizedBox(height: 8),
        const Text('Visao geral',
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
                child: _metric('JOGOS', '${_matches.length}', 'na base local')),
            const SizedBox(width: 10),
            Expanded(
                child: _metric('SINAIS ATIVOS', '$activeSignals', 'regra v1')),
            const SizedBox(width: 10),
            Expanded(child: _metric('RESULTADOS', '$completed', 'registrados')),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Jogos em analise',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            TextButton(
                onPressed: () => setState(() => _tab = 1),
                child: const Text('Ver todos')),
          ],
        ),
        if (upcoming.isEmpty) _emptyState() else ...upcoming.map(_matchTile),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EDE7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Estimativas usam somente os gols esperados informados por voce. Nao ha dados ao vivo nem garantia de resultado.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _matchesView(List<MatchRecord> matches) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Text('REGISTRO LOCAL', style: _eyebrowStyle),
          const SizedBox(height: 8),
          const Text('Jogos',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          if (matches.isEmpty) _emptyState() else ...matches.map(_matchTile),
        ],
      );

  Widget _signalsView() {
    final signals = _matches
        .where((match) => !match.hasResult)
        .expand((match) {
          final forecast = ForecastEngine.calculate(
            homeExpectedGoals: match.homeXg,
            awayExpectedGoals: match.awayXg,
          );
          return forecast.signals.map((signal) => (match, signal));
        })
        .where((entry) => entry.$2.isActive)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        Text('REGRAS T01-T05', style: _eyebrowStyle),
        const SizedBox(height: 8),
        const Text('Sinais ativos',
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
            'Limiares fixos do modelo inicial. Revise-os com backtests antes de usar.',
            style: TextStyle(color: Color(0xFF66716B), height: 1.4)),
        const SizedBox(height: 18),
        if (signals.isEmpty)
          _emptyState(message: 'Nenhum sinal atingiu os limiares atuais.')
        else
          ...signals.map((entry) => _signalTile(entry.$1, entry.$2)),
      ],
    );
  }

  Widget _validationView() {
    final report = _backtestReport ??= WalkForwardBacktest.run(_matches);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        Text('AVALIACAO TEMPORAL', style: _eyebrowStyle),
        const SizedBox(height: 8),
        const Text('Backtest e calibracao',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Previsoes sao ordenadas por data. Cada ajuste usa somente resultados anteriores, sem consultar o placar da propria partida.',
          style: TextStyle(color: Color(0xFF66716B), height: 1.4),
        ),
        const SizedBox(height: 18),
        if (report.rows.isEmpty)
          _emptyState(
              message:
                  'Registre resultados para iniciar a avaliacao cronologica.')
        else ...[
          Row(children: [
            Expanded(
                child: _metric(
                    'PARTIDAS', '${report.rows.length}', 'com resultado')),
            const SizedBox(width: 10),
            Expanded(
                child: _metric('BRIER BASE', report.rawBrier.toStringAsFixed(3),
                    'menor e melhor')),
            const SizedBox(width: 10),
            Expanded(
                child: _metric(
                    'ACERTO 1X2',
                    '${(report.accuracy * 100).toStringAsFixed(1)}%',
                    'argmax sem ajuste')),
          ]),
          const SizedBox(height: 10),
          _metric(
              'BRIER WALK-FORWARD',
              report.calibratedBrier.toStringAsFixed(3),
              report.calibratedBrier < report.rawBrier
                  ? 'ajuste melhora nesta amostra'
                  : 'ajuste nao melhora nesta amostra'),
          const SizedBox(height: 25),
          const Text('Calibracao por faixa',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
              'Probabilidade media comparada a frequencia observada; categorias 1, X e 2 sao agrupadas separadamente.',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF66716B), height: 1.4)),
          const SizedBox(height: 12),
          ...report.calibrationBins.map((bin) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  SizedBox(
                      width: 35,
                      child: Text(bin.outcome,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  Expanded(
                      child: Text(
                          '${(bin.lowerBound * 100).round()}-${(bin.upperBound * 100).round()}% previsto',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF66716B)))),
                  Text(
                      '${(bin.meanProbability * 100).round()}% / ${(bin.observedRate * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('n=${bin.count}',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF66716B))),
                ]),
              )),
          const SizedBox(height: 16),
          const Text(
              'Calibracao e avaliacao dependem da qualidade e do volume da base importada. Uma amostra pequena nao valida o modelo.',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF66716B), height: 1.4)),
        ],
      ],
    );
  }

  Widget _metric(String label, String value, String footnote) => Container(
        constraints: const BoxConstraints(minHeight: 94),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E6E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF66716B))),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            Text(footnote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF66716B))),
          ],
        ),
      );

  Widget _matchTile(MatchRecord match) {
    final forecast = ForecastEngine.calculate(
      homeExpectedGoals: match.homeXg,
      awayExpectedGoals: match.awayXg,
    );
    final active = forecast.signals.where((signal) => signal.isActive).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E6E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(match.competition.toUpperCase(),
                      style: _eyebrowStyle)),
              Text(match.kickoff,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF66716B))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Text(match.homeTeam,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))),
              Text(
                  match.hasResult
                      ? '${match.homeScore} : ${match.awayScore}'
                      : 'vs',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFF16785B))),
              Expanded(
                  child: Text(match.awayTeam,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 7, runSpacing: 6, children: [
            _probabilityChip('1', forecast.homeWin),
            _probabilityChip('X', forecast.draw),
            _probabilityChip('2', forecast.awayWin),
            _probabilityChip('O2.5', forecast.overTwoFive),
          ]),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                active
                    .map((signal) => '${signal.code} ${signal.label}')
                    .join('  /  '),
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF16785B),
                    fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _recordResult(match),
              icon: const Icon(Icons.edit_note, size: 18),
              label: Text(
                  match.hasResult ? 'Editar resultado' : 'Registrar resultado'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _probabilityChip(String label, double value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0xFFF0F3EE),
            borderRadius: BorderRadius.circular(5)),
        child: Text('$label ${(value * 100).round()}%',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _signalTile(MatchRecord match, ForecastSignal signal) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFFE5F1EA),
                  borderRadius: BorderRadius.circular(5)),
              child: Text(signal.code,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFF16785B))),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(signal.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${match.homeTeam} x ${match.awayTeam}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF66716B))),
                ])),
            Text('${(signal.probability * 100).round()}%',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _emptyState(
          {String message =
              'Cadastre um jogo para calcular probabilidades e sinais.'}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            const Icon(Icons.sports_soccer_outlined,
                size: 30, color: Color(0xFF16785B)),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF66716B), height: 1.4)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: _addMatch,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar jogo')),
          ],
        ),
      );

  TextStyle get _eyebrowStyle => const TextStyle(
        fontSize: 10,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w800,
        color: Color(0xFF66716B),
      );
}

class AddMatchSheet extends StatefulWidget {
  const AddMatchSheet({super.key});

  @override
  State<AddMatchSheet> createState() => _AddMatchSheetState();
}

class _AddMatchSheetState extends State<AddMatchSheet> {
  final _formKey = GlobalKey<FormState>();
  final _competition = TextEditingController();
  final _home = TextEditingController();
  final _away = TextEditingController();
  final _homeXg = TextEditingController(text: '1.4');
  final _awayXg = TextEditingController(text: '1.1');
  final _kickoff = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));

  @override
  void dispose() {
    _competition.dispose();
    _home.dispose();
    _away.dispose();
    _homeXg.dispose();
    _awayXg.dispose();
    _kickoff.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obrigatorio' : null;

  String? _competitionValidator(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final competition = value!.toLowerCase();
    if (competition.contains('srl') || competition.contains('simulad')) {
      return 'Competicoes SRL ou simuladas nao sao aceitas';
    }
    return null;
  }

  String? _date(String? value) {
    if (_required(value) != null || DateTime.tryParse(value!.trim()) == null) {
      return 'Informe uma data ISO valida';
    }
    return null;
  }

  String? _expectedGoals(String? value) {
    final number = double.tryParse((value ?? '').replaceAll(',', '.'));
    if (number == null || !number.isFinite || number < 0 || number > 10) {
      return 'Informe um valor entre 0 e 10';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MatchRecord(
        competition: _competition.text.trim(),
        homeTeam: _home.text.trim(),
        awayTeam: _away.text.trim(),
        homeXg: double.parse(_homeXg.text.replaceAll(',', '.')),
        awayXg: double.parse(_awayXg.text.replaceAll(',', '.')),
        kickoff: DateTime.parse(_kickoff.text.trim()).toIso8601String(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Novo jogo',
                    style:
                        TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Informe suas estimativas de gols esperados.',
                    style: TextStyle(color: Color(0xFF66716B))),
                const SizedBox(height: 18),
                _field(_competition, 'Competicao',
                    validator: _competitionValidator),
                const SizedBox(height: 10),
                _field(_kickoff, 'Data (AAAA-MM-DD)', validator: _date),
                const SizedBox(height: 10),
                _field(_home, 'Time da casa', validator: _required),
                const SizedBox(height: 10),
                _field(_away, 'Time visitante', validator: _required),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _field(_homeXg, 'Gols esperados casa',
                          validator: _expectedGoals, numeric: true)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _field(_awayXg, 'Gols esperados fora',
                          validator: _expectedGoals, numeric: true)),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: _save,
                        child: const Text('Calcular e salvar'))),
              ],
            ),
          ),
        ),
      );

  Widget _field(TextEditingController controller, String label,
          {String? Function(String?)? validator, bool numeric = false}) =>
      TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      );
}

class ResultDialog extends StatefulWidget {
  const ResultDialog({
    super.key,
    this.initialHomeScore,
    this.initialAwayScore,
  });

  final int? initialHomeScore;
  final int? initialAwayScore;

  @override
  State<ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<ResultDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _home;
  late final TextEditingController _away;

  @override
  void initState() {
    super.initState();
    _home =
        TextEditingController(text: widget.initialHomeScore?.toString() ?? '');
    _away =
        TextEditingController(text: widget.initialAwayScore?.toString() ?? '');
  }

  @override
  void dispose() {
    _home.dispose();
    _away.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Resultado final'),
        content: Form(
          key: _formKey,
          child: Row(children: [
            Expanded(
              child: TextFormField(
                controller: _home,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Casa'),
                validator: _scoreValidator,
              ),
            ),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(':')),
            Expanded(
              child: TextFormField(
                controller: _away,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Visitante'),
                validator: _scoreValidator,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              final home = int.parse(_home.text.trim());
              final away = int.parse(_away.text.trim());
              Navigator.pop(context, (home, away));
            },
            child: const Text('Salvar'),
          ),
        ],
      );

  String? _scoreValidator(String? value) {
    final score = int.tryParse((value ?? '').trim());
    if (score == null || score < 0) return 'Use inteiro >= 0';
    return null;
  }
}
