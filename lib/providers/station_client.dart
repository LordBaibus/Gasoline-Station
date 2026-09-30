import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/station_status.dart';

/// Base URL of the Flask REST API running on the Raspberry Pi.
///
/// The Pi runs its own WiFi access point (NetworkManager 'shared' mode)
/// instead of joining a home router's network, so its address is fixed
/// by that AP config ('ipv4.addresses 192.168.4.1/24') rather than
/// assigned by a router's DHCP. The phone must be connected to the
/// Pi's own WiFi network (its SSID, e.g. 'GasStationPi') for this to
/// be reachable — this is much closer to how the old ESP32
/// access-point setup worked than a shared-router setup is.
const String stationBaseUrl = 'http://192.168.4.1:5000';

/// How often the homepage/settings pages poll GET /api/status.
/// 1500ms was chosen as a balance between "feels live" and not hammering
/// the Pi's single-worker Flask server with requests.
const Duration pollInterval = Duration(milliseconds: 1500);

/// Timeout for individual HTTP calls. Kept short because on a local
/// network a slow response almost always means the Pi/server is
/// unreachable, not genuinely slow — no reason to make the user wait.
const Duration requestTimeout = Duration(seconds: 3);

class StationApiClient {
  final http.Client _http = http.Client();

  Future<StationStatus> fetchStatus() async {
    final uri = Uri.parse('$stationBaseUrl/api/status');
    final response = await _http.get(uri).timeout(requestTimeout);

    if (response.statusCode != 200) {
      throw StationApiException(
        'Status request failed with code ${response.statusCode}',
      );
    }

    final Map<String, dynamic> json =
    jsonDecode(response.body) as Map<String, dynamic>;
    return StationStatus.fromJson(json);
  }

  /// Sets a single fuel price. Returns the updated prices reported back
  /// by the server so the UI reflects exactly what was saved and shown
  /// on the display, not just what we asked for.
  ///
  /// The Flask backend writes to MySQL and to the TM1637 display in the
  /// same request, so a 200 means both succeeded; a 207 means one half
  /// (db_saved or display_updated) failed — surfaced here as an
  /// exception with the detail included so the UI can tell the user
  /// what specifically went wrong.
  Future<FuelPrices> setPrice({
    required String fuelType,
    required double price,
  }) async {
    final uri = Uri.parse('$stationBaseUrl/api/prices');
    final response = await _http
        .post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fuel_type': fuelType, 'price': price}),
    )
        .timeout(requestTimeout);

    final Map<String, dynamic> json =
    jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 400) {
      final String errorMsg = json['error'] as String? ?? 'Invalid request';
      throw StationApiException(errorMsg);
    }

    if (response.statusCode == 207) {
      final bool dbSaved = json['db_saved'] as bool? ?? false;
      final bool displayUpdated = json['display_updated'] as bool? ?? false;
      if (!dbSaved) {
        throw StationApiException(
          'Could not save the price to the database.',
        );
      }
      if (!displayUpdated) {
        throw StationApiException(
          'Price saved, but the display could not be updated.',
        );
      }
    } else if (response.statusCode != 200) {
      throw StationApiException(
        'Request failed with code ${response.statusCode}',
      );
    }

    // /api/prices only confirms the single changed price, not the full
    // set — re-fetch status right after calling this (station_provider
    // already does) to get the complete, server-confirmed FuelPrices.
    final double confirmedPrice = (json['price'] as num).toDouble();
    switch (fuelType) {
      case 'diesel':
        return FuelPrices(
          diesel: confirmedPrice,
          unleaded: 0,
          gasoline: 0,
        );
      case 'unleaded':
        return FuelPrices(
          diesel: 0,
          unleaded: confirmedPrice,
          gasoline: 0,
        );
      default:
        return FuelPrices(
          diesel: 0,
          unleaded: 0,
          gasoline: confirmedPrice,
        );
    }
  }

  void dispose() => _http.close();
}

class StationApiException implements Exception {
  final String message;
  StationApiException(this.message);
  @override
  String toString() => message;
}

final stationClientProvider = Provider<StationApiClient>((ref) {
  final client = StationApiClient();
  ref.onDispose(client.dispose);
  return client;
});