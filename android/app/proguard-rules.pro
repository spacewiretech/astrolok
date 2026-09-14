# Cashfree PG SDK.
#
# The SDK resolves payment classes reflectively and communicates with the gateway over
# Gson-serialised models, so R8 strips exactly the classes it needs: a minified release build
# fails at the UPI handoff with no error a user could report. Circle 360 ships without these
# rules, which is a latent bug there — it just has not had minification turned on.
-keep class com.cashfree.pg.** { *; }
-dontwarn com.cashfree.pg.**

# Gson's reflective (de)serialisation of the SDK's model classes.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Fields named only in JSON are otherwise unreferenced and get renamed.
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# flutter_secure_storage delegates to the AndroidX security library.
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# Google Play Install Referrer, behind `play_install_referrer`.
#
# Release builds run R8 with `isMinifyEnabled` and `isShrinkResources` on. The referrer client is
# reached over an AIDL service binding, so nothing in this app statically references the generated
# stub classes and R8 removes them — leaving a plugin that throws at the moment it is asked for
# the referrer, in release only. A debug build attributes installs correctly and the store build
# silently does not, which is the worst possible way to discover a keep rule is missing.
-keep class com.android.installreferrer.** { *; }
-dontwarn com.android.installreferrer.**
