import 'package:flutter/material.dart';
import '../../players/model/player.dart';
import '../model/match_game.dart';
import '../model/match_event.dart';

class MatchDialog extends StatefulWidget {
  const MatchDialog({
    super.key,
    required this.match,
    required this.teamName,
    required this.homePlayers,
    required this.awayPlayers,
    required this.onSave,
  });

  final MatchGame match;
  final String Function(int) teamName;
  final List<Player> homePlayers;
  final List<Player> awayPlayers;
  final VoidCallback onSave;

  @override
  State<MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<MatchDialog> {
  late int home;
  late int away;

  @override
  void initState() {
    super.initState();
    home = widget.match.homeScore;
    away = widget.match.awayScore;
  }

  Future<void> _addGoal(int teamIndex) async {
    final players = teamIndex == widget.match.homeIndex
        ? widget.homePlayers
        : widget.awayPlayers;

    if (players.isEmpty) return;

    final scorer = await _pickPlayer(players, 'Кто забил?');
    if (scorer == null) return;

    final assist = await _pickPlayer(
      players,
      'Кто отдал пас?',
      allowSkip: true,
    );

    setState(() {
      if (teamIndex == widget.match.homeIndex) {
        home++;
      } else {
        away++;
      }

      widget.match.events.add(
        MatchEvent.goal(
          teamIndex: teamIndex,
          playerId: scorer.id,
          playerName: scorer.name,
          assistPlayerId: assist?.id,
          assistPlayerName: assist?.name,
        ),
      );
    });
  }

  void _addOwnGoal(int benefitingTeam) {
    setState(() {
      if (benefitingTeam == widget.match.homeIndex) {
        home++;
      } else {
        away++;
      }

      widget.match.events.add(MatchEvent.ownGoal(teamIndex: benefitingTeam));
    });
  }

  void _undoLast() {
    if (widget.match.events.isEmpty) return;

    final last = widget.match.events.removeLast();

    setState(() {
      final affectsScore =
          last.type == MatchEventType.goal ||
          last.type == MatchEventType.ownGoal;
      if (!affectsScore) return;

      if (last.teamIndex == widget.match.homeIndex) {
        if (home > 0) home--;
      } else {
        if (away > 0) away--;
      }
    });
  }

  Future<Player?> _pickPlayer(
    List<Player> players,
    String title, {
    bool allowSkip = false,
  }) {
    return showDialog<Player>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: players.length + (allowSkip ? 1 : 0),
            itemBuilder: (context, i) {
              if (allowSkip && i == players.length) {
                return ListTile(
                  title: const Text('Без ассиста'),
                  onTap: () => Navigator.pop(context),
                );
              }

              final p = players[i];
              return ListTile(
                title: Text(p.name),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${widget.teamName(widget.match.homeIndex)} vs '
        '${widget.teamName(widget.match.awayIndex)}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$home : $away',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _addGoal(widget.match.homeIndex),
                child: Text('+ Гол ${widget.teamName(widget.match.homeIndex)}'),
              ),
              ElevatedButton(
                onPressed: () => _addGoal(widget.match.awayIndex),
                child: Text('+ Гол ${widget.teamName(widget.match.awayIndex)}'),
              ),
              OutlinedButton(
                onPressed: () => _addOwnGoal(widget.match.homeIndex),
                child: const Text('+ Автогол хозяевам'),
              ),
              OutlinedButton(
                onPressed: () => _addOwnGoal(widget.match.awayIndex),
                child: const Text('+ Автогол гостям'),
              ),
              TextButton(
                onPressed: _undoLast,
                child: const Text('↩ Отменить последнее'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            widget.match.homeScore = home;
            widget.match.awayScore = away;
            widget.match.finished = true;

            widget.onSave();
            Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
