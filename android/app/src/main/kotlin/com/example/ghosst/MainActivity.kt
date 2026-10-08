package com.protech.ghosst

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.security.cert.CertificateFactory

// Cold-start integrity gate for release builds.
//
// A repacked/cracked APK is ALWAYS re-signed with somebody else's key
// (Android will not install it otherwise — the v2/v3 signing block covers
// every byte of the APK). So the signing certificate is the load-bearing
// signal: it catches "mod", "repack", "patched dex", pirate-store builds.
//
// Two cheap secondary signals back it up: a debuggable build, and an APK
// that arrived through a known patching tool.
//
// Deliberately NOT checked (per product decision): root, Xposed/Frida,
// emulators, installer=sideload. Those flag legitimate users as often as
// crackers — the signature already settles the question.
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "verifyIntegrity" -> result.success(verifyIntegrity())
                    "uninstallSelf" -> result.success(uninstallSelf())
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------- verdict

    // Returns `{ blocked: bool, flags: List<String> }` — Dart turns the
    // flags into user-facing reasons on the block screen.
    private fun verifyIntegrity(): Map<String, Any> {
        val flags = mutableListOf<String>()

        // A modded build is often renamed so it installs NEXT TO the official
        // app (cracked clones). Must match `applicationId` in build.gradle.kts.
        if (packageName != APPLICATION_ID) flags.add("package-changed")

        // Release builds are never debuggable; a rebuilt debug APK is.
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            flags.add("debuggable-build")
        }

        // The load-bearing one: re-signed APK → not our certificate.
        if (!signatureMatchesOfficial()) flags.add("signature-mismatch")

        // Installed straight out of a patching tool (never a normal source).
        installerPackage()?.let { installer ->
            if (MOD_INSTALLERS.contains(installer.lowercase())) {
                flags.add("mod-installer:$installer")
            }
        }

        return mapOf("blocked" to (flags.isNotEmpty()), "flags" to flags)
    }

    // Uninstalls this copy via the system confirmation sheet. Needed because
    // a re-signed build CANNOT install over the official app — the user has
    // to remove this one first (Android refuses `INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
    private fun uninstallSelf(): Boolean = try {
        val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName"))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    // ------------------------------------------------------------- signature

    private fun signatureMatchesOfficial(): Boolean {
        // Unreadable signature info (locked-down ROM, odd install path):
        // fail OPEN. A broken check must never brick a legitimate install.
        val signatures = currentSignatures() ?: return true
        if (signatures.isEmpty()) return false
        return signatures.any { OFFICIAL_SHA256.contains(certificateSha256(it)) }
    }

    @Suppress("DEPRECATION")
    private fun currentSignatures(): Array<Signature>? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager
                .getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo
                ?.apkContentsSigners
        } else {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
        }
    } catch (e: Exception) {
        null
    }

    // SHA-256 over the signing certificate's DER encoding (hex, uppercase).
    private fun certificateSha256(signature: Signature): String {
        val raw = signature.toByteArray()
        val der = try {
            CertificateFactory.getInstance("X.509")
                .generateCertificate(raw.inputStream())
                .encoded
        } catch (e: Exception) {
            // Some paths hand back the certificate bytes directly.
            raw
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(der)
            .joinToString("") { "%02X".format(it.toInt() and 0xFF) }
    }

    // -------------------------------------------------------------- installer

    @Suppress("DEPRECATION")
    private fun installerPackage(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            packageManager.getInstallerPackageName(packageName)
        }
    } catch (e: Exception) {
        null
    }

    companion object {
        private const val CHANNEL = "com.protech.ghosst/security"

        // Keep in sync with `applicationId` in android/app/build.gradle.kts.
        private const val APPLICATION_ID = "com.protech.ghosst"

        // SHA-256 of the official release certificate (`ghosst-release.jks`,
        // alias `ghosst`). Re-derive any time the keystore changes:
        //   keytool -list -v -keystore ghosst-release.jks -alias ghosst
        private val OFFICIAL_SHA256 = setOf(
            "A1353756EFD6A4107553F35C10483B87D6A7600E7FAD6DDD1AA99B8DFAA2E123",
        )

        // Installers that only ever deliver re-packaged builds. Sideload
        // sources (Chrome, Files, package managers) are deliberately absent —
        // that's how every official install arrives.
        private val MOD_INSTALLERS = setOf(
            "com.chelpus.lackypatch", // Lucky Patcher
            "com.dimonvideo.luckypatcher", // Lucky Patcher
            "org.droidsmith.luckypatcher", // Lucky Patcher
            "com.gmail.heagoo.apkeditorpro", // APK Editor Pro
            "com.gmail.heagoo.apkeditor", // APK Editor
            "com.apkeditor.pro", // APK Editor Pro (alt id)
        )
    }
}
