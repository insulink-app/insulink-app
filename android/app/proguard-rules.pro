# Google MLKit barcode scanning (used by mobile_scanner to read the sensor-box
# DataMatrix). Flutter enables R8 for release builds, and mobile_scanner's own
# bundled keep rules use a single-star wildcard (`com.google.mlkit.*`) that does
# NOT cover the barcode subpackages or the `com.google.android.gms.internal.
# mlkit_*` implementation classes the model loads reflectively. R8 then strips
# the whole pipeline and MLKit throws a null-object NPE the moment the camera
# opens in release. Keep the full MLKit surface.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# flutter_local_notifications: its background ActionBroadcastReceiver (the path
# that fires when a notification's action BUTTON is tapped, e.g. the "training
# detected" Confirm/Discard buttons) reconstructs the notification's action data
# via Gson reflection. In release, R8 strips/obfuscates those model classes and
# Gson's generic TypeToken machinery, so the action handler never runs and the
# buttons appear dead — while the identical in-app Dart confirm/reject still
# works (it never touches this native path). Keep the plugin + Gson reflection.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.dexterous.**
