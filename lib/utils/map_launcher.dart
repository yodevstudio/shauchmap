import 'dart:io';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';

enum TravelMode { driving, walking, bicycling }

class MapLauncher {
  static Future<void> launch({
    required LatLng destination,
    required String toiletName,
    required String toiletId,
    required int etaSeconds,
    required TravelMode mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Save pending review info
    await prefs.setString('pending_review_toilet_id', toiletId);
    await prefs.setString('pending_review_toilet_name', toiletName);

    final eligibleTime = DateTime.now()
        .add(Duration(seconds: etaSeconds))
        .add(const Duration(minutes: 2));
    await prefs.setInt(
      'pending_review_eligible_time',
      eligibleTime.millisecondsSinceEpoch,
    );

    await NotificationService().scheduleRateVisitNudge();

    // Generate OS specific link
    final lat = destination.latitude;
    final lng = destination.longitude;

    String androidMode;
    String iosMode;
    String webMode;
    switch (mode) {
      case TravelMode.driving:
        androidMode = 'd';
        iosMode = 'driving';
        webMode = 'driving';
        break;
      case TravelMode.walking:
        androidMode = 'w';
        iosMode = 'walking';
        webMode = 'walking';
        break;
      case TravelMode.bicycling:
        androidMode = 'b';
        iosMode = 'bicycling';
        webMode = 'bicycling';
        break;
    }

    final androidUri = Uri.parse(
      'google.navigation:q=$lat,$lng&mode=$androidMode',
    );
    final iosUri = Uri.parse(
      'comgooglemaps://?daddr=$lat,$lng&directionsmode=$iosMode',
    );
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=$webMode',
    );

    try {
      if (Platform.isIOS) {
        if (!await launchUrl(iosUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      } else if (Platform.isAndroid) {
        if (!await launchUrl(androidUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }
}
