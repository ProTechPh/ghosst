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

# Appwrite & Networking
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# File picker & platform interface
-keep class com.mr.flutter.plugin.filepicker.** { *; }
