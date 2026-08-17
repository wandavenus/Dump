plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.wndavenz.music"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.wndavenz.music"
        minSdk = 27
        targetSdk = 36
        versionCode = 1
        versionName = "1.5.30"

        ndk {
            abiFilters.add("arm64-v8a")
        }

        buildConfigField("boolean", "MEDIA3_FFMPEG_DECODER_LINKED", "true")

        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=c++_static")
                cppFlags("-std=c++17")
                abiFilters.add("arm64-v8a")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/DEPENDENCIES",
                "META-INF/*.version",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
        jniLibs {
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**"
            )
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.coroutines.android)

    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.session)
    implementation(libs.androidx.media3.ui)
    implementation(libs.androidx.media3.extractor)

    implementation(libs.jellyfin.media3.ffmpeg.decoder) {
        exclude(group = "androidx.media3", module = "media3-decoder")
        exclude(group = "androidx.media3", module = "media3-exoplayer")
    }

    implementation(libs.androidx.palette)
    implementation(libs.gson)
    implementation(libs.coil.compose)

    debugImplementation(libs.androidx.ui.tooling)
}
