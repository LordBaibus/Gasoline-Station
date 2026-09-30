import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../models/station_status.dart';
import '../providers/station_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/status_row.dart';

class Settings extends ConsumerStatefulWidget {
  const Settings({super.key});

  @override
  ConsumerState<Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<Settings> {
  @override
  Widget build(BuildContext context) {
    final status = ref.watch(stationProvider);

    return CupertinoPageScaffold(
      backgroundColor: GulfColors.blue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: GulfColors.white,
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Device'),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              children: [
                StatusRow(
                  label: 'Raspberry Pi server',
                  status: status.serverConnected
                      ? SensorStatus.connected
                      : SensorStatus.disconnected,
                ),
                const _RowDivider(),
                StatusRow(
                  label: 'MySQL database',
                  status: status.dbConnected
                      ? SensorStatus.connected
                      : SensorStatus.disconnected,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const _SectionLabel('Price displays'),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              children: [
                StatusRow(label: 'Diesel', status: status.displays.diesel),
                const _RowDivider(),
                StatusRow(
                  label: 'Premium',
                  status: status.displays.gasoline,
                ),
                const _RowDivider(),
                StatusRow(
                  label: 'Unleaded',
                  status: status.displays.unleaded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: GulfColors.blueLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GulfColors.border),
        ),
        child: child,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: GulfColors.whiteMuted,
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Container(
        height: 0.5,
        color: GulfColors.border,
      ),
    );
  }
}