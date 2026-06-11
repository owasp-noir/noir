plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.ktsapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.ktsapp"
        minSdk = 24
        targetSdk = 34

        manifestPlaceholders["authHost"] = "auth.example.com"
        manifestPlaceholders += mapOf("authScheme" to "ktsauth")
        manifestPlaceholders.put("legacyScheme", "ktslegacy")
    }
}
