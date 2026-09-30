library;

enum SensorStatus { connected, disconnected, faulty }

SensorStatus sensorStatusFromString(String? raw) {
  switch (raw) {
    case 'connected':
      return SensorStatus.connected;
    case 'faulty':
      return SensorStatus.faulty;
    default:
      return SensorStatus.disconnected;
  }
}

class FuelPrices {
  final double diesel;
  final double unleaded;
  final double gasoline;

  const FuelPrices({
    required this.diesel,
    required this.unleaded,
    required this.gasoline,
  });

  factory FuelPrices.fromJson(Map<String, dynamic> json) {
    return FuelPrices(
      diesel: (json['diesel'] as num?)?.toDouble() ?? 0.0,
      unleaded: (json['unleaded'] as num?)?.toDouble() ?? 0.0,
      gasoline: (json['gasoline'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory FuelPrices.zero() =>
      const FuelPrices(diesel: 0, unleaded: 0, gasoline: 0);
}

class DisplayStatusSet {
  final SensorStatus diesel;
  final SensorStatus unleaded;
  final SensorStatus gasoline;

  const DisplayStatusSet({
    required this.diesel,
    required this.unleaded,
    required this.gasoline,
  });

  factory DisplayStatusSet.fromJson(Map<String, dynamic> json) {
    return DisplayStatusSet(
      diesel: sensorStatusFromString(json['diesel'] as String?),
      unleaded: sensorStatusFromString(json['unleaded'] as String?),
      gasoline: sensorStatusFromString(json['gasoline'] as String?),
    );
  }

  factory DisplayStatusSet.allDisconnected() => const DisplayStatusSet(
    diesel: SensorStatus.disconnected,
    unleaded: SensorStatus.disconnected,
    gasoline: SensorStatus.disconnected,
  );
}
class StationStatus {
  final bool serverConnected;
  final bool dbConnected;
  final FuelPrices prices;
  final DisplayStatusSet displays;
  final int uptimeMs;
  final DateTime fetchedAt;

  const StationStatus({
    required this.serverConnected,
    required this.dbConnected,
    required this.prices,
    required this.displays,
    required this.uptimeMs,
    required this.fetchedAt,
  });
  factory StationStatus.fromJson(Map<String, dynamic> json) {
    return StationStatus(
      serverConnected: json['server_connected'] as bool? ?? false,
      dbConnected: json['db_connected'] as bool? ?? false,
      prices: FuelPrices.fromJson(
        json['prices'] as Map<String, dynamic>? ?? {},
      ),
      displays: DisplayStatusSet.fromJson(
        json['displays'] as Map<String, dynamic>? ?? {},
      ),
      uptimeMs: (json['uptime_ms'] as num?)?.toInt() ?? 0,
      fetchedAt: DateTime.now(),
    );
  }
  factory StationStatus.disconnected() {
    return StationStatus(
      serverConnected: false,
      dbConnected: false,
      prices: FuelPrices.zero(),
      displays: DisplayStatusSet.allDisconnected(),
      uptimeMs: 0,
      fetchedAt: DateTime.now(),
    );
  }
}