# ML Kit text recognition ships optional script models (Chinese, Japanese,
# Korean, Devanagari) that Markless doesn't bundle — only Latin is used.
# R8 sees the plugin reference them and fails the build without this.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.vision.text.** { *; }
