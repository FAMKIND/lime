import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Backend config: the same public values ios/generate.sh reads (the anon key ships inside apps by design).
// A missing file still builds; the app then says "No backend configured". Never hard-code these.
val backendEnv: Map<String, String> = file("../../supabase/.staging.public.env").takeIf { it.exists() }
    ?.readLines().orEmpty()
    .mapNotNull { line -> line.trim().takeIf { it.isNotEmpty() && !it.startsWith("#") && "=" in it } }
    .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim().trim('"', '\'') }

android {
    namespace = "com.limemessenger.lime"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.limemessenger.lime"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "BACKEND_URL", "\"${backendEnv["SUPABASE_URL"].orEmpty()}\"")
        buildConfigField("String", "BACKEND_API_KEY", "\"${backendEnv["SUPABASE_ANON_KEY"].orEmpty()}\"")
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }

    // Signing (LIME-411): the release build is signed only when ~/.lime/android-signing.properties exists (storeFile, storePassword, keyAlias, keyPassword); without it the bundle is
    // unsigned. Nothing secret is in the repo. The real Play UPLOAD key is the owner's, made when the Play account exists; the file may point at a local test keystore until then.
    val signingFile = File(System.getProperty("user.home"), ".lime/android-signing.properties")
    val signing = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }
    signingConfigs {
        if (signingFile.exists()) create("lime") {
            storeFile = file(signing.getProperty("storeFile"))
            storePassword = signing.getProperty("storePassword")
            keyAlias = signing.getProperty("keyAlias")
            keyPassword = signing.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("lime")?.let { signingConfig = it }
        }
        // The release build with the debug key, for proving that R8 did not break the app: the instrumented suite runs against it (-Plime.testBuildType=releaseLike).
        // The tests link to app classes by name, so this type additionally keeps the app's own classes from being renamed or removed; libraries (JNA, CameraX, Media3,
        // Compose) are shrunk and optimized exactly as in release, and so are the resources.
        create("releaseLike") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
            matchingFallbacks += "release"
            proguardFiles("proguard-test-keep.pro")
        }
    }
    if (project.hasProperty("lime.testBuildType")) testBuildType = project.property("lime.testBuildType") as String
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    sourceSets["main"].kotlin.directories.add("build/generated/uniffi")
    // releaseLike is a release (the stub of the debug-only test sign-in, no test accounts) that the instrumented tests can run against.
    sourceSets["releaseLike"].kotlin.directories.add("src/release/java")
    // Test doubles shared by the unit tests and the instrumented UI tests.
    sourceSets["test"].kotlin.directories.add("src/testShared/java")
    sourceSets["androidTest"].kotlin.directories.add("src/testShared/java")
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

// Builds liblime_core.so + the UniFFI Kotlin bindings before anything compiles.
val buildCore = tasks.register<Exec>("buildCore") {
    workingDir = rootDir
    commandLine("sh", "build-core.sh")
    inputs.files(fileTree("../../core/src"), file("../../core/Cargo.toml"), file("../../core/Cargo.lock"))
    outputs.dir("src/main/jniLibs")
    outputs.dir("build/generated/uniffi")
}
tasks.named("preBuild") { dependsOn(buildCore) }

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.biometric)
    // LIME-314: video messages. CameraX records; Media3 (ExoPlayer) plays. Both are AndroidX: no Google Play services, no analytics.
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.video)
    implementation(libs.androidx.camera.view)
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(libs.kotlinx.coroutines.android)
    // 1:1 calls (LIME-425): Google's libwebrtc as LiveKit's SDK ships it (BSD-3), so group calls (LIME-428) add no second copy of the native code.
    implementation(libs.webrtc)
    implementation("net.java.dev.jna:jna:${libs.versions.jna.get()}@aar")

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.json)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    "releaseLikeImplementation"(libs.androidx.compose.ui.test.manifest)   // the compose tests' empty activity, for the releaseLike type only
}
