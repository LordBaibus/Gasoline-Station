import 'package:flutter/cupertino.dart';
import '../models/station_status.dart';
import '../providers/theme_provider.dart';

/// A single status row: label on the left, colored dot + status word on
/// the right. Used for the Raspberry Pi server/database connection and
/// the TM1637 displays on the settings page. Kept as a plain
/// CupertinoListTile-style row per the liquid_glass_widgets docs' own
/// guidance for settings screens ("use CupertinoListTile or standard
/// Flutter containers for the rows").
class StatusRow extends StatelessWidget {
  final String label;
  final SensorStatus status;

  const StatusRow({super.key, required this.label, required this.status});

  ({Color color, String text}) get _display {
    switch (status) {
      case SensorStatus.connected:
        return (color: GulfColors.success, text: 'Connected');
      case SensorStatus.faulty:
        return (color: GulfColors.orange, text: 'Faulty');
      case SensorStatus.disconnected:
        return (color: GulfColors.whiteFaint, text: 'Disconnected');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _display;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: GulfColors.white,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: d.color),
          ),
          Text(
            d.text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: d.color,
            ),
          ),
        ],
      ),
    );
  }
}