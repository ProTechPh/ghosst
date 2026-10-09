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
    return ConsentInformation.instance.canRequestAds();
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
}
