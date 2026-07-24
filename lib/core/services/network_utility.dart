import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkUtility {
  static final NetworkUtility instance = NetworkUtility._();
  NetworkUtility._();

  /// Checks if there is a local hardware connection AND actual internet backhaul
  Future<bool> hasInternetAccess() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.every((result) => result == ConnectivityResult.none)) {
        debugPrint('🔌 Network check: Local interface is offline.');
        return false;
      }

      // Perform reliable lookups to test actual internet connectivity.
      // Lookup 1.1.1.1 (Cloudflare DNS) first, as it is extremely fast and reliable.
      try {
        final result = await InternetAddress.lookup('one.one.one.one')
            .timeout(const Duration(seconds: 2));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          debugPrint('🌐 Internet check: Active internet backhaul verified via Cloudflare DNS.');
          return true;
        }
      } catch (_) {
        // Fallback to Google DNS lookup
      }

      try {
        final result = await InternetAddress.lookup('dns.google')
            .timeout(const Duration(seconds: 2));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          debugPrint('🌐 Internet check: Active internet backhaul verified via Google DNS.');
          return true;
        }
      } catch (_) {
        // Fallback to a standard web domain lookup
      }

      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 2));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          debugPrint('🌐 Internet check: Active internet backhaul verified via google.com.');
          return true;
        }
      } catch (_) {
        // If all lookups fail, there is no real internet connection
      }

      debugPrint('🔌 Network check: Connected to network but actual internet is unreachable (portal or no backhaul).');
      return false;
    } catch (e) {
      debugPrint('⚠️ Error during internet lookup: $e');
      return false;
    }
  }
}
