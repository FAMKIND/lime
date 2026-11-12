# LIME-411: only for the `releaseLike` build type (the instrumented tests link to the app's classes by name).
-keep class com.limemessenger.lime.** { *; }
-dontwarn com.limemessenger.lime.**
# The test APK is compiled against these and finds them in the app's process, so they stay whole in this build type only. (JNA, UniFFI's glue, CameraX, Media3 and the rest of AndroidX are shrunk and optimized as in release.)
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-keep class androidx.compose.** { *; }
-keep class androidx.activity.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**
-keep class androidx.collection.** { *; }
-keep class androidx.core.** { *; }
-keep class androidx.savedstate.** { *; }
-keep class androidx.arch.** { *; }
