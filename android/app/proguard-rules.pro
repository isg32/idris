
# NewPipeExtractor and the Rhino JavaScript engine it runs YouTube's player
# code in (rules from NewPipe's own proguard-rules.pro).
# NewPipe ships with obfuscation off; Idris keeps the extractor whole
# instead, so nothing it looks up by name is renamed.
-keep class org.schabi.newpipe.extractor.** { *; }
-keep class com.grack.nanojson.** { *; }
-keep class org.mozilla.javascript.* { *; }
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.javascript.engine.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-dontwarn org.mozilla.javascript.JavaToJSONConverters
-dontwarn org.mozilla.javascript.tools.**
-keep class javax.script.** { *; }
-dontwarn javax.script.**
-keep class jdk.dynalink.** { *; }
-dontwarn jdk.dynalink.**
-dontwarn okhttp3.**
-dontwarn okio.**
