plugins {
    id("com.android.application")
}

android {
    // The id below is a constant reference (not a string literal), resolved
    // from buildSrc (Constants.kt). The manifest has no `package` attribute,
    // so the package falls back to this resolved value.
    defaultConfig {
        applicationId = APP_ID
        minSdk = 24
    }
}
