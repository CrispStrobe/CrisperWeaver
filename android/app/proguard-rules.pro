# CrisperWeaver ProGuard rules for release builds.

# Keep whisper / CrispASR native methods
-keep class com.crispstrobe.crisperweaver.WhisperCppPlugin { *; }
-keepclassmembers class com.crispstrobe.crisperweaver.WhisperCppPlugin {
    native <methods>;
}

# Keep all native method declarations (CrispASR + CrispEmbed FFI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter plugins — keep plugin registrants
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# Just Audio (audio playback)
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Share plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# Path provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Keep Kotlin metadata (required for some plugins)
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Keep R8 from stripping FFI-accessed classes
-keep class dart.** { *; }
