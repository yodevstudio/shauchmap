# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.internal.firebase** { *; }
-dontwarn com.google.firebase.**

# Google Maps / Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Geolocator
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# General Android
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# WorkManager — callbackDispatcher must survive R8
-keep class be.tramckrijte.workmanager.** { *; }
-keepnames class io.flutter.plugins.workmanager.** { *; }

# home_widget — widget update and click receivers
-keep class es.antonborri.home_widget.** { *; }

# speech_to_text — native speech recognition bindings
-keep class com.csdcorp.speech_to_text.** { *; }

# flutter_local_notifications — BroadcastReceivers for scheduled notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# flutter_timezone — getLocalTimezone() call
-keep class com.jcho1823.flutter_timezone.** { *; }
-dontwarn com.sun.jna.**

# app_links — deep link intent handling on cold start
-keep class com.llfbandit.app_links.** { *; }

# geocoding — reverse geocoding in add wizard
-keep class com.baseflow.geocoding.** { *; }

# connectivity_plus — network state monitoring
-keep class dev.fluttercommunity.plus.connectivity.** { *; }