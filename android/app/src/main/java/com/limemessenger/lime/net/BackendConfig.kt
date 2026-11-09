package com.limemessenger.lime.net

import com.limemessenger.lime.BuildConfig

/** Where the backend is. Both values are public by design (the anon key ships inside apps); they come from the build (see app/build.gradle.kts). */
data class BackendConfig(val url: String, val apiKey: String) {
    companion object {
        /** null when the build was made without a backend file ("No backend configured"). */
        val current: BackendConfig? =
            if (BuildConfig.BACKEND_URL.isNotEmpty() && BuildConfig.BACKEND_API_KEY.isNotEmpty())
                BackendConfig(BuildConfig.BACKEND_URL, BuildConfig.BACKEND_API_KEY) else null
    }
}
