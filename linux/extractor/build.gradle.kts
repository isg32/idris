// The YouTube extractor for Idris on Linux: NewPipe Extractor (the same
// library the Android app uses, see android/app/build.gradle.kts) behind a
// line-based JSON protocol on stdin/stdout. lib/platform/desktop_extractor.dart
// starts it; linux/build_appimage.sh bundles it with a trimmed Java runtime.
//
// Build: ./android/gradlew -p linux/extractor installDist
plugins {
    application
}

repositories {
    mavenCentral()
    maven("https://jitpack.io")
}

dependencies {
    // Keep in step with android/app/build.gradle.kts.
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.27.0")
    // Its JSON library, which the protocol uses too (NewPipe's version).
    implementation("com.github.TeamNewPipe:nanojson:e9d656ddb49a412a5a0a5d5ef20ca7ef09549996")
}

java {
    toolchain { languageVersion = JavaLanguageVersion.of(17) }
}

application {
    mainClass = "com.isg32.idris.Extractor"
}
