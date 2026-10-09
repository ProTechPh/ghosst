# Flutter and Plugin rules
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keepattributes *Annotation*

# Google Mobile Ads SDK rules
-keep public class com.google.android.gms.ads.** {
   public *;
}
-keep public class com.google.ads.** {
   public *;
}
-keepattributes *Annotation*
-dontwarn com.google.android.gms.**
-dontwarn com.google.ads.**

# Unity Ads Mediation rules
-keep class com.unity3d.ads.** { *; }
-keep class com.unity3d.services.** { *; }
-keep class com.google.ads.mediation.unity.** { *; }
-dontwarn com.unity3d.ads.**
-dontwarn com.unity3d.services.**
-dontwarn com.google.ads.mediation.unity.**

# Appwrite & Networking
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# File picker & platform interface
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# androidx.work + androidx.room: WorkManagerInitializer builds WorkDatabase at
# process start through Room's reflective lookup of the generated *_Impl class.
# If R8 strips or renames those, the app force-closes before Flutter even
# starts: "Failed to create an instance of androidx.work.impl.WorkDatabase".
# WorkManager's initializer runs unconditionally via androidx.startup.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# Play Core split-install classes are referenced by Flutter's deferred-component
# loader but not shipped (we don't use dynamic feature modules). Suppress only —
# kept in sync with build/app/outputs/mapping/<variant>/missing_rules.txt.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
