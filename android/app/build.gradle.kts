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

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    sourceSets["main"].kotlin.directories.add("build/generated/uniffi")
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
    implementation(libs.kotlinx.coroutines.android)
    implementation("net.java.dev.jna:jna:${libs.versions.jna.get()}@aar")

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.json)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
