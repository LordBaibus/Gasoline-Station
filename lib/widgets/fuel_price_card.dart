import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../providers/theme_provider.dart';

/// Displays one fuel type's current price as a Gulf-branded "pump
/// display" card — a solid Gulf-orange panel on the page's Gulf-blue
/// background, with white text and icons throughout, matching the
/// station's canopy fascia (orange panel against the blue canopy).
/// Tapping the price opens an edit sheet, which is styled to match the
/// rest of the app (Gulf blue/orange, rounded cards) instead of a stock
/// iOS alert. Submitting calls [onPriceChanged], which the caller wires
/// to the station provider's setPrice (which pushes to the Flask
/// backend, which writes to MySQL and the physical TM1637 display).
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
    await showCupertinoModalPopup<void>(
      context: context,
      barrierColor: CupertinoColors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _PriceEditSheet(
        label: label,
        initialPrice: price,
        onSubmit: onPriceChanged,
      ),
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

/// Allows only digits and a single decimal point with at most 2 decimal
/// places — stricter than the plain numberWithOptions(decimal: true)
/// keyboard, which still lets a user type "65.7.5" or "65....".
class _PriceInputFormatter extends TextInputFormatter {
  static final RegExp _pattern = RegExp(r'^\d{0,2}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    if (newValue.text.isEmpty) return newValue;
    if (_pattern.hasMatch(newValue.text)) return newValue;
    return oldValue;
  }
}

/// Gulf-branded bottom sheet for editing one fuel type's price. Replaces
/// the previous stock CupertinoAlertDialog, which looked like a default
/// system alert dropped onto an otherwise fully-branded app. This sheet
/// reuses the same orange "pump display" language as the card it was
/// opened from, adds quick ±0.25/±1.00 steppers (the two most common
/// adjustments at a real station), and gives validation errors a visible
/// red-bordered treatment instead of a small caption line.
class _PriceEditSheet extends StatefulWidget {
  final String label;
  final double initialPrice;
  final ValueChanged<double> onSubmit;

  const _PriceEditSheet({
    required this.label,
    required this.initialPrice,
    required this.onSubmit,
  });

  @override
  State<_PriceEditSheet> createState() => _PriceEditSheetState();
}

class _PriceEditSheetState extends State<_PriceEditSheet> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    // Repaints the input's border when focus changes (e.g. user taps
    // elsewhere), so the orange "focused" outline clears correctly
    // instead of staying lit until some other setState happens to fire.
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double? get _parsedValue => double.tryParse(_controller.text.trim());

  void _applyDelta(double delta) {
    final current = _parsedValue ?? widget.initialPrice;
    final next = (current + delta).clamp(0.0, 99.99);
    setState(() {
      _controller.text = next.toStringAsFixed(2);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _errorText = null;
    });
  }

  void _submit() {
    final parsed = _parsedValue;
    if (parsed == null) {
      setState(() => _errorText = 'Enter a valid number');
      return;
    }
    if (parsed < 0 || parsed > 99.99) {
      setState(() => _errorText = 'Must be between ₱0.00 and ₱99.99');
      return;
    }
    Navigator.of(context).pop();
    widget.onSubmit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasError = _errorText != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: GulfColors.blue,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: GulfColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              // Grab handle, signals "sheet" rather than "alert".
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: GulfColors.whiteFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: GulfColors.orange.withValues(alpha: 0.22),
                          ),
                          child: const Icon(
                            CupertinoIcons.gauge,
                            color: GulfColors.orange,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.label.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: GulfColors.whiteMuted,
                                ),
                              ),
                              const Text(
                                'Set new price',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: GulfColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: GulfColors.white.withValues(alpha: 0.10),
                            ),
                            child: const Icon(
                              CupertinoIcons.xmark,
                              color: GulfColors.whiteMuted,
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // The price input itself — large, orange-on-blue,
                    // reading like the physical TM1637 pump display this
                    // value is about to be pushed to, with a fixed peso
                    // prefix instead of asking the user to type it.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: GulfColors.blueLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasError
                              ? GulfColors.danger
                              : (_focusNode.hasFocus
                              ? GulfColors.orange
                              : GulfColors.border),
                          width: hasError || _focusNode.hasFocus ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '₱',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: GulfColors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [_PriceInputFormatter()],
                              decoration: const BoxDecoration(),
                              padding: EdgeInsets.zero,
                              placeholder: '0.00',
                              placeholderStyle: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: GulfColors.whiteFaint,
                              ),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: GulfColors.white,
                              ),
                              cursorColor: GulfColors.orange,
                              onChanged: (_) {
                                if (hasError) setState(() => _errorText = null);
                              },
                              onSubmitted: (_) => _submit(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (hasError) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_circle_fill,
                            color: GulfColors.danger,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _errorText!,
                            style: const TextStyle(
                              color: GulfColors.danger,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Range: ₱0.00–₱99.99 · updates the display instantly',
                        style: TextStyle(
                          fontSize: 12,
                          color: GulfColors.whiteMuted,
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Quick-adjust steppers — the two increments a real
                    // station actually re-prices by, so the attendant
                    // rarely needs to retype the whole number.
                    Row(
                      children: [
                        Expanded(
                          child: _StepperButton(
                            label: '−1.00',
                            onTap: () => _applyDelta(-1.00),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StepperButton(
                            label: '−0.25',
                            onTap: () => _applyDelta(-0.25),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StepperButton(
                            label: '+0.25',
                            onTap: () => _applyDelta(0.25),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StepperButton(
                            label: '+1.00',
                            onTap: () => _applyDelta(1.00),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: _SheetActionButton(
                            label: 'Cancel',
                            filled: false,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SheetActionButton(
                            label: 'Save price',
                            filled: true,
                            onTap: _submit,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StepperButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 10),
      borderRadius: BorderRadius.circular(10),
      color: GulfColors.white.withValues(alpha: 0.10),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: GulfColors.white,
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _SheetActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 14),
      borderRadius: BorderRadius.circular(14),
      color: filled ? GulfColors.orange : GulfColors.white.withValues(alpha: 0.08),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: filled ? GulfColors.white : GulfColors.whiteMuted,
        ),
      ),
    );
  }
}