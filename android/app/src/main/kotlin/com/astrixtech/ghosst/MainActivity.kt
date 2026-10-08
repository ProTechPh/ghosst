package com.astrixtech.ghosst

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
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
                    "getPrivateDns" -> result.success(privateDns())
                    else -> result.notImplemented()
                }
            }

        // Official-APK download: the system DownloadManager writes straight
        // into public Downloads, so the file outlives this (modified) copy
        // and survives the uninstall step of the recovery flow.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val url = call.argument<String>("url")
                        val name = call.argument<String>("name")
                        if (url.isNullOrBlank() || name.isNullOrBlank()) {
                            result.error("bad-args", "url and name are required", null)
                        } else {
                            try {
                                result.success(startApkDownload(url, name))
                            } catch (e: Exception) {
                                result.error(
                                    "download-failed",
                                    e.message ?: "Could not start the download",
                                    null,
                                )
                            }
                        }
                    }
                    "status" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id == null) {
                            result.error("bad-args", "id is required", null)
                        } else {
                            try {
                                result.success(apkDownloadStatus(id))
                            } catch (e: Exception) {
                                result.error("status-failed", e.message ?: "Unknown error", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------- download

    // Enqueues the official APK with the system DownloadManager: no storage
    // permission (targetSdk ≥ Q), progress comes from the system notification
    // too, and the file lands in public Downloads where it survives the
    // uninstall this screen is about to ask for.
    private fun startApkDownload(url: String, fileName: String): Long {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("Ghosst — official app")
            .setDescription("Saving the official APK to your Downloads folder…")
            .setMimeType(APK_MIME)
            // Visible while it runs AND after it finishes: the completion
            // notification is what the user taps to install once this copy
            // has been removed.
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
        return dm.enqueue(request)
    }

    private fun apkDownloadStatus(id: Long): Map<String, Any> {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = dm.query(DownloadManager.Query().setFilterById(id))
            ?: return mapOf("state" to "missing")
        return cursor.use {
            if (!it.moveToFirst()) return@use mapOf<String, Any>("state" to "missing")
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val received =
                it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total =
                it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val localUri = it.getString(it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                ?: ""
            val state = when (status) {
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_PAUSED -> "paused"
                else -> "running"
            }
            mapOf<String, Any>(
                "state" to state,
                "received" to received,
                "total" to if (total > 0) total else 0L,
                "message" to if (state == "failed") downloadErrorText(reason) else "",
                "uri" to localUri,
            )
        }
    }

    private fun downloadErrorText(reason: Int): String = when (reason) {
        DownloadManager.ERROR_INSUFFICIENT_SPACE -> "Not enough storage space"
        DownloadManager.ERROR_DEVICE_NOT_FOUND -> "Storage is not available"
        DownloadManager.ERROR_FILE_ERROR -> "Could not save the file"
        DownloadManager.ERROR_CANNOT_RESUME -> "The download could not be resumed"
        DownloadManager.ERROR_UNHANDLED_HTTP_CODE,
        DownloadManager.ERROR_HTTP_DATA_ERROR,
        -> "The download server returned an error"
        else -> "Download failed (error $reason)"
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
    //
    // Falls back down the chain because Android 11+ package visibility hides
    // the uninstall activity from apps that never declared it in <queries>:
    // ACTION_DELETE throws ActivityNotFoundException, and some ROMs route it
    // somewhere else entirely. The app-info page is the universal last resort
    // (it carries the same Uninstall button).
    private fun uninstallSelf(): Boolean {
        val pkgUri = Uri.parse("package:$packageName")
        val attempts = listOf(
            Intent(Intent.ACTION_DELETE, pkgUri),
            Intent("android.intent.action.UNINSTALL_PACKAGE", pkgUri),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri),
        )
        for (intent in attempts) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // try the next one
            }
        }
        return false
    }

    // ----------------------------------------------------------- private DNS

    // Custom Private DNS (e.g. dns.adguard.com) is the usual way ads get
    // filtered device-wide. Read-only, no permission needed. Purely
    // informational: it names the server on the ad-blocker gate, never
    // triggers it — a privacy-only DNS server is not a blocker.
    private fun privateDns(): Map<String, String?>? = try {
        mapOf(
            "mode" to Settings.Global.getString(contentResolver, "private_dns_mode"),
            "specifier" to Settings.Global.getString(contentResolver, "private_dns_specifier"),
        )
    } catch (e: Exception) {
        // Locked-down ROM / unreadable setting — Dart skips the enrichment.
        null
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
        private const val CHANNEL = "com.astrixtech.ghosst/security"
        private const val APK_CHANNEL = "com.astrixtech.ghosst/apk"
        private const val APK_MIME = "application/vnd.android.package-archive"

        // Keep in sync with `applicationId` in android/app/build.gradle.kts.
        private const val APPLICATION_ID = "com.astrixtech.ghosst"

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
