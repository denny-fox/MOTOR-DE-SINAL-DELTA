class MatchRecord {
  const MatchRecord({
    this.id,
    required this.competition,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeXg,
    required this.awayXg,
    required this.kickoff,
    this.homeScore,
    this.awayScore,
  });

  final int? id;
  final String competition;
  final String homeTeam;
  final String awayTeam;
  final double homeXg;
  final double awayXg;
  final String kickoff;
  final int? homeScore;
  final int? awayScore;

  bool get hasResult => homeScore != null && awayScore != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'competition': competition,
        'home_team': homeTeam,
        'away_team': awayTeam,
        'home_xg': homeXg,
        'away_xg': awayXg,
        'kickoff': kickoff,
        'home_score': homeScore,
        'away_score': awayScore,
      };

  factory MatchRecord.fromMap(Map<String, Object?> map) => MatchRecord(
        id: map['id'] as int?,
        competition: map['competition'] as String,
        homeTeam: map['home_team'] as String,
        awayTeam: map['away_team'] as String,
        homeXg: (map['home_xg'] as num).toDouble(),
        awayXg: (map['away_xg'] as num).toDouble(),
        kickoff: map['kickoff'] as String,
        homeScore: map['home_score'] as int?,
        awayScore: map['away_score'] as int?,
      );
}
