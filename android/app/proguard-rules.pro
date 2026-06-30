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
