import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacePrediction {
  final String description;
  final String placeId;

  PlacePrediction({required this.description, required this.placeId});

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      description: json['description'],
      placeId: json['place_id'],
    );
  }
}

class LocationResult {
  final double lat;
  final double lng;

  LocationResult({required this.lat, required this.lng});
}

class PlacesService {
  // Injected at build time: flutter run --dart-define=PLACES_API_KEY=AIza…
  // Never hardcode here — the Places key has billing attached.
  static const String _apiKey = String.fromEnvironment(
    'PLACES_API_KEY',
    defaultValue: '',
  );

  static Future<List<PlacePrediction>> getAutocomplete(String input) async {
    if (input.isEmpty) return [];

    final String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$_apiKey';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List)
              .map((p) => PlacePrediction.fromJson(p))
              .toList();
        }
      }
    } catch (e) {
      // Fallthrough to empty list on error
    }
    return const [];
  }

  static Future<LocationResult?> getPlaceLocation(String placeId) async {
    final String url =
        'https://maps.googleapis.com/maps/api/geocode/json?place_id=$placeId&key=$_apiKey';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return LocationResult(lat: location['lat'], lng: location['lng']);
        }
      }
    } catch (e) {
      // Fallthrough to null on error
    }
    return null;
  }

  static Future<LocationResult?> geocodeAddress(String address) async {
    if (address.isEmpty) return null;

    final String url =
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$_apiKey';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return LocationResult(lat: location['lat'], lng: location['lng']);
        }
      }
    } catch (e) {
      // Fallthrough to null on error
    }
    return null;
  }

  static Future<String?> getNearbyLandmark(double lat, double lng) async {
    final String url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=$lat,$lng'
        '&rankby=distance'
        '&keyword=gas+station+OR+temple+OR+church+OR+hospital+OR+bank+OR+school'
        '&key=$_apiKey';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final firstResult = data['results'][0];
          return firstResult['name']?.toString();
        }
      }
    } catch (e) {
      // Silently catch network failures
    }
    return null;
  }
}
