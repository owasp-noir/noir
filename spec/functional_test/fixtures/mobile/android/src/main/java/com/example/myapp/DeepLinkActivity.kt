package com.example.myapp

import android.app.Activity
import android.os.Bundle
import android.webkit.WebView

class DeepLinkActivity : Activity() {
    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val data = intent.data
        val target = data?.getQueryParameter("redirect")
        val campaign = data?.getQueryParameter("utm_source")
        val userId = intent.getStringExtra("userId")
        val verified = intent.getBooleanExtra("verified", false)
        val id = data?.lastPathSegment
        renderProfile(id, userId)
        if (target != null) {
            webView.loadUrl(target)
        }
    }

    private fun renderProfile(id: String?, userId: String?) {
        webView.loadData("<h1>" + id + "</h1>", "text/html", "utf-8")
    }
}
