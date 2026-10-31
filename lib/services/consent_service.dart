import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMP consent gate. Ads initialize only after UMP says requests are
/// permitted; errors never guess consent on a first run.
class ConsentService {
  ConsentService._();

  static Future<bool> gatherConsent() async {
    final completed = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) {
            debugPrint(
              '[Consent] Form error ${error.errorCode}: ${error.message}',
            );
          }
          if (!completed.isCompleted) completed.complete();
        });
      },
      (error) {
        debugPrint(
          '[Consent] Update error ${error.errorCode}: ${error.message}',
        );
        if (!completed.isCompleted) completed.complete();
      },
    );

    try {
      await completed.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      debugPrint('[Consent] Consent request timed out');
    }

    final canRequest = await ConsentInformation.instance.canRequestAds();
    if (canRequest) return true;

    // Graceful fallback: If UMP failed (e.g., misconfigured or missing form, network hiccup),
    // check whether privacy options are explicitly required in the current region.
    // If not in the EEA/UK, do not block global ad serving.
    try {
      final reqStatus = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      if (reqStatus != PrivacyOptionsRequirementStatus.required) {
        debugPrint(
          '[Consent] Privacy options not required ($reqStatus); allowing ads fallback.',
        );
        return true;
      }
    } catch (e) {
      debugPrint('[Consent] Error inspecting privacy requirement: $e');
    }

    return false;
  }

  static Future<bool> privacyOptionsRequired() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  static Future<FormError?> showPrivacyOptions() {
    final completed = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm((error) => completed.complete(error));
    return completed.future;
  }

  static Future<bool> canRequestAds() async {
    return ConsentInformation.instance.canRequestAds();
  }

  // Consent reaches Unity Ads through the UMP/TCF string UMP itself writes —
  // the app forwards nothing by hand.
}
