# LIME-411: keep rules for the release build (R8). Only what is reached by name, reflection or native code.

# UniFFI: the generated bindings (LimeCore) call into the native library by name, and the native library calls back into these classes.
-keep class uniffi.lime_core.** { *; }
-keep interface uniffi.lime_core.** { *; }

# JNA (UniFFI's bridge): it finds native methods, structures and callbacks by reflection.
-dontwarn java.awt.*
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }

# Media3 and CameraX ship their own consumer rules (they are AndroidX); nothing more is needed here.

# WebRTC (LIME-425): the native library (liblkjingle_peerconnection_so) calls these Java classes by name (and loads jni_zero's at JNI_OnLoad: R8 removed it and the process aborted).
-keep class livekit.org.webrtc.** { *; }
-keep class livekit.org.jni_zero.** { *; }
-dontwarn livekit.org.**
