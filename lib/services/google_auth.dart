import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In: ang app lang ang kumuha ng ID token — ang API
/// (`POST /v1/auth/google`) ang nagbe-verify at nagmint ng session, kaya walang
/// Google secret sa app.
///
/// Ito ang **Web** OAuth client ng project (pareho ng nasa
/// `ghosst-web/config/google_oauth.php`) at kailangang tugma sa
/// `GOOGLE_CLIENT_ID` sa `api/config.php`.
const googleServerClientId =
    '578056640322-1lkus4sngk496sn29fqmor6ab13nkgfk.apps.googleusercontent.com';

class GoogleAuth {
  static bool _initialized = false;

  /// Null kapag walang idToken na ibinigay si Google. Nagta-throw ng
  /// [GoogleSignInException] kapag kinansel o hindi available ang Play services.
  static Future<String?> idToken() async {
    final signIn = GoogleSignIn.instance;
    if (!_initialized) {
      await signIn.initialize(serverClientId: googleServerClientId);
      _initialized = true;
    }
    final account = await signIn.authenticate();
    final token = account.authentication.idToken;
    try {
      // Ang token lang ang kailangan natin; iwanang malinis para makapili
      // muli ng account sa susunod na sign-in.
      await signIn.signOut();
    } catch (_) {}
    return token;
  }
}
