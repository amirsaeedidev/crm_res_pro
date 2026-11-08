# Flutter's Android embedding includes optional Play Store deferred-component
# integration. This app does not ship deferred components, so these Play Core
# APIs are not required at runtime. Suppress R8 missing-class diagnostics for
# the optional integration instead of packaging an unused legacy Play Core SDK.
-dontwarn com.google.android.play.core.**
