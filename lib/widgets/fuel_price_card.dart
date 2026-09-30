import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../providers/theme_provider.dart';

/// Displays one fuel type's current price as a Gulf-branded "pump
/// display" card — a solid Gulf-orange panel on the page's Gulf-blue
/// background, with white text and icons throughout, matching the
/// station's canopy fascia (orange panel against the blue canopy).
/// Tapping the price opens an edit dialog; submitting calls
/// [onPriceChanged], which the caller wires to the station provider's
/// setPrice (which pushes to the Flask backend, which writes to MySQL
/// and the physical TM1637 display).
class FuelPriceCard extends StatelessWidget {
  final String label;
  final double price;
  final bool isConnected;
  final ValueChanged<double> onPriceChanged;

  const FuelPriceCard({
    super.key,
    required this.label,
    required this.price,
    required this.isConnected,
    required this.onPriceChanged,
  });

  Color get _iconCircleColor => isConnected
      ? GulfColors.white.withValues(alpha: 0.22)
      : GulfColors.white.withValues(alpha: 0.10);

  String get _displayPrice =>
      isConnected ? '₱${price.toStringAsFixed(2)}' : '₱--.--';

  Future<void> _openEditSheet(BuildContext context) async {
    final controller = TextEditingController(text: price.toStringAsFixed(2));
    String? errorText;

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: Text('Set $label price'),
              content: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CupertinoTextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      placeholder: 'e.g. 65.75',
                      autofocus: true,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: GulfColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'Range: 0.00 to 99.99 (display shows 2 decimals)',
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () {
                    final parsed = double.tryParse(controller.text.trim());
                    if (parsed == null) {
                      setDialogState(() => errorText = 'Enter a valid number');
                      return;
                    }
                    if (parsed < 0 || parsed > 99.99) {
                      setDialogState(
                            () => errorText = 'Must be between 0.00 and 99.99',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    onPriceChanged(parsed);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnected ? () => _openEditSheet(context) : null,
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Container(
          padding: const EdgeInsets.all(16),
          // Always fully opaque Gulf orange — a semi-transparent orange
          // here used to composite with the page's blue underneath
          // (through the glass layer) and render as a muddy brown/grey
          // instead of a paler orange. "Disconnected" is communicated
          // through the content alone (dimmer text, the --.-- price
          // placeholder, and the tap being disabled), not by fading the
          // panel.
          decoration: BoxDecoration(
            color: GulfColors.orange,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _iconCircleColor,
                ),
                child: Icon(
                  CupertinoIcons.gauge,
                  color: isConnected
                      ? GulfColors.white
                      : GulfColors.whiteFaint,
                  size: 22,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isConnected
                            ? GulfColors.whiteMuted
                            : GulfColors.whiteFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayPrice,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: isConnected
                            ? GulfColors.white
                            : GulfColors.whiteFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.pencil_circle,
                color: isConnected ? GulfColors.white : GulfColors.whiteFaint,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}