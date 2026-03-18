# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase basics (though R8 usually handles this)
-keepattributes Signature,Annotation
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Agora
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Common 
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**
