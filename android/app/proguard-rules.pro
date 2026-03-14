# --- 1. BẢO VỆ MEDIAPIPE TẬN RĂNG ---
-keep class com.google.mediapipe.** { *; }
-keepclassmembers class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# --- 2. BẢO VỆ FLOGGER (THỦ PHẠM GÂY LỖI "no caller found") ---
-keep class com.google.common.flogger.** { *; }
-keepclassmembers class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**

# --- 3. BẢO VỆ GUAVA (LÕI CỦA FLOGGER) ---
-keep class com.google.common.** { *; }
-keepclassmembers class com.google.common.** { *; }
-dontwarn com.google.common.**

# --- 4. BẢO VỆ PROTOBUF & AUTOVALUE ---
-keep class com.google.protobuf.** { *; }
-keepclassmembers class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
-keep class com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**

# --- 5. BẢO VỆ CÁC HÀM NATIVE (JNI C++) ---
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}