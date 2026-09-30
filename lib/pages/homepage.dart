import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/station_provider.dart';
import '../providers/station_client.dart';
import '../providers/theme_provider.dart';
import '../widgets/fuel_price_card.dart';

class Homepage extends ConsumerStatefulWidget {
  const Homepage({super.key});

  @override
  ConsumerState<Homepage> createState() => _HomepageState();
}

class _HomepageState extends ConsumerState<Homepage> {
  bool _isSavingPrice = false;

  Future<void> _handlePriceChange(String fuelType, double newPrice) async {
    setState(() => _isSavingPrice = true);
    try {
      await ref.read(stationProvider.notifier).setPrice(
        fuelType: fuelType,
        price: newPrice,
      );
    } on StationApiException catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) {
        _showError('Could not reach the station server. Check the WiFi connection.');
      }
    } finally {
      if (mounted) setState(() => _isSavingPrice = false);
    }
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Could not update price'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(stationProvider);
    final bool isConnected = status.serverConnected && status.dbConnected;

    return CupertinoPageScaffold(
      backgroundColor: GulfColors.blue,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () => ref.read(stationProvider.notifier).refreshNow(),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _GulfHeaderBanner(isConnected: isConnected),
                const SizedBox(height: 24),

                const Text(
                  'Fuel prices',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: GulfColors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap a price to update it — changes push to the display instantly.',
                  style: TextStyle(
                    fontSize: 13,
                    color: GulfColors.whiteMuted,
                  ),
                ),
                const SizedBox(height: 16),
                FuelPriceCard(
                  label: 'Diesel',
                  price: status.prices.diesel,
                  isConnected: isConnected && !_isSavingPrice,
                  onPriceChanged: (p) => _handlePriceChange('diesel', p),
                ),
                const SizedBox(height: 12),
                FuelPriceCard(
                  label: 'Premium',
                  price: status.prices.gasoline,
                  isConnected: isConnected && !_isSavingPrice,
                  onPriceChanged: (p) => _handlePriceChange('gasoline', p),
                ),
                const SizedBox(height: 12),
                FuelPriceCard(
                  label: 'Unleaded',
                  price: status.prices.unleaded,
                  isConnected: isConnected && !_isSavingPrice,
                  onPriceChanged: (p) => _handlePriceChange('unleaded', p),
                ),

                if (!isConnected) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GulfColors.blueLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: GulfColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.wifi_slash,
                          color: GulfColors.orange,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            !status.serverConnected
                                ? 'Not connected to the station server. Make sure your phone and the Raspberry Pi are on the same WiFi network, then pull to refresh.'
                                : 'Connected to the server, but its database is unreachable.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: GulfColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gulf-branded header banner: orange panel with the disc-style
/// wordmark, echoing the canopy fascia signage in the reference photo —
/// now the one orange surface on an otherwise all-blue page, so it reads
/// as the station's identity mark rather than blending into the
/// background.
class _GulfHeaderBanner extends StatelessWidget {
  final bool isConnected;
  const _GulfHeaderBanner({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [GulfColors.orange, GulfColors.orangeDark],
        ),
      ),
      child: Row(
        children: [
          // The Gulf disc logo already carries its own white ring and
          // orange disc, so it's placed directly rather than nested
          // inside another white circle (which would double up the
          // background behind it).
          Image.asset(
            'assets/images/gulf_logo.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GULF SERVICE CENTER',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: GulfColors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Station control',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: GulfColors.white,
                  ),
                ),
              ],
            ),
          ),
          _ConnectionPill(isConnected: isConnected),
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  final bool isConnected;
  const _ConnectionPill({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? GulfColors.success : GulfColors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: GulfColors.blue.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Live' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}