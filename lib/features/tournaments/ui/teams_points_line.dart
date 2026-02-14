import 'package:flutter/material.dart';

class TeamsPointsLine extends StatelessWidget {
  final Map<String, int> pointsByTeam;

  /// Внешний вид "чипов"
  final double chipRadius;
  final EdgeInsets chipPadding;
  final double gap;

  const TeamsPointsLine({
    super.key,
    required this.pointsByTeam,
    this.chipRadius = 10,
    this.chipPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (pointsByTeam.isEmpty) return const SizedBox.shrink();

    final maxPoints = pointsByTeam.values.reduce((a, b) => a > b ? a : b);

    // Важно: порядок будет таким, как ты положил в Map (если кладешь A,B,C,D — будет A,B,C,D).
    final entries = pointsByTeam.entries.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            _PointsChip(
              label: '${entries[i].key}-${entries[i].value}',
              isLeader: entries[i].value == maxPoints,
              radius: chipRadius,
              padding: chipPadding,
            ),
            if (i != entries.length - 1) SizedBox(width: gap),
          ],
        ],
      ),
    );
  }
}

class _PointsChip extends StatelessWidget {
  final String label;
  final bool isLeader;
  final double radius;
  final EdgeInsets padding;

  const _PointsChip({
    required this.label,
    required this.isLeader,
    required this.radius,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isLeader
        ? Colors.green.withOpacity(0.15)
        : Colors.grey.withOpacity(0.12);

    final border = isLeader
        ? Colors.green.withOpacity(0.55)
        : Colors.grey.withOpacity(0.25);

    final textColor = isLeader
        ? Colors.green.shade800
        : Theme.of(context).textTheme.bodySmall?.color;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: isLeader ? FontWeight.w700 : FontWeight.w500,
            ),
      ),
    );
  }
}
