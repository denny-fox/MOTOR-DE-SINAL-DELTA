import 'dart:convert';

import 'package:csv/csv.dart';

import '../models/match_record.dart';

class MatchImporter {
  static const csvHeaders = [
    'competition',
    'home_team',
    'away_team',
    'home_xg',
    'away_xg',
    'kickoff',
    'home_score',
    'away_score',
  ];

  static List<MatchRecord> parse(String content, {required String extension}) {
    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    final records = switch (normalizedExtension) {
      'json' => _parseJson(content),
      'csv' => _parseCsv(content),
      _ => throw const FormatException('Formato invalido. Use CSV ou JSON.'),
    };
    if (records.isEmpty) {
      throw const FormatException('O arquivo nao contem partidas.');
    }
    return records;
  }

  static List<MatchRecord> _parseJson(String content) {
    final decoded = jsonDecode(content);
    final rows = decoded is List
        ? decoded
        : decoded is Map<String, dynamic> && decoded['matches'] is List
            ? decoded['matches'] as List
            : throw const FormatException(
                'JSON deve ser uma lista ou conter a chave "matches".');
    return rows.asMap().entries.map((entry) {
      if (entry.value is! Map) {
        throw FormatException(
            'Partida ${entry.key + 1}: esperado um objeto JSON.');
      }
      final row = <String, Object?>{};
      (entry.value as Map).forEach((key, value) {
        row[key.toString().toLowerCase().trim()] = value;
      });
      try {
        return _record(row);
      } on FormatException catch (error) {
        throw FormatException('Partida ${entry.key + 1}: ${error.message}');
      }
    }).toList();
  }

  static List<MatchRecord> _parseCsv(String content) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(content);
    final nonEmptyRows = rows
        .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    if (nonEmptyRows.length < 2) {
      throw const FormatException(
          'CSV precisa de cabecalho e ao menos uma partida.');
    }
    final headers = nonEmptyRows.first
        .map((cell) =>
            cell.toString().replaceFirst('\uFEFF', '').trim().toLowerCase())
        .toList();
    if (headers.toSet().length != headers.length) {
      throw const FormatException('CSV nao pode conter cabecalhos duplicados.');
    }
    final missing =
        csvHeaders.where((header) => !headers.contains(header)).toList();
    if (missing.isNotEmpty) {
      throw FormatException(
          'Colunas obrigatorias ausentes: ${missing.join(', ')}.');
    }
    return nonEmptyRows.skip(1).toList().asMap().entries.map((entry) {
      if (entry.value.length != headers.length) {
        throw FormatException(
            'Linha ${entry.key + 2}: numero de colunas diferente do cabecalho.');
      }
      final values = <String, Object?>{};
      for (var index = 0; index < headers.length; index++) {
        values[headers[index]] = entry.value[index].toString().trim();
      }
      try {
        return _record(values);
      } on FormatException catch (error) {
        throw FormatException('Linha ${entry.key + 2}: ${error.message}');
      }
    }).toList();
  }

  static MatchRecord _record(Map<String, Object?> row) {
    String text(String key) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isEmpty || value.toLowerCase() == 'null') {
        throw FormatException('campo "$key" obrigatorio.');
      }
      return value;
    }

    double decimal(String key) {
      final value = double.tryParse(text(key).replaceAll(',', '.'));
      if (value == null || !value.isFinite || value < 0 || value > 10) {
        throw FormatException('"$key" deve estar entre 0 e 10.');
      }
      return value;
    }

    int? score(String key) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isEmpty || value.toLowerCase() == 'null') return null;
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 0) {
        throw FormatException('"$key" deve ser um inteiro nao negativo.');
      }
      return parsed;
    }

    final competition = text('competition');
    final normalizedCompetition = competition.toLowerCase();
    if (normalizedCompetition.contains('srl') ||
        normalizedCompetition.contains('simulad')) {
      throw const FormatException(
          'competicoes SRL ou simuladas nao sao aceitas.');
    }
    final kickoff = text('kickoff');
    if (DateTime.tryParse(kickoff) == null) {
      throw const FormatException(
          '"kickoff" deve ser uma data ISO 8601 valida.');
    }
    final homeScore = score('home_score');
    final awayScore = score('away_score');
    if ((homeScore == null) != (awayScore == null)) {
      throw const FormatException(
          'informe os dois placares ou deixe ambos vazios.');
    }

    return MatchRecord(
      competition: competition,
      homeTeam: text('home_team'),
      awayTeam: text('away_team'),
      homeXg: decimal('home_xg'),
      awayXg: decimal('away_xg'),
      kickoff: DateTime.parse(kickoff).toIso8601String(),
      homeScore: homeScore,
      awayScore: awayScore,
    );
  }
}
