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
        val id = data?.lastPathSegment
        renderProfile(id)
        if (target != null) {
            webView.loadUrl(target)
        }
    }

    private fun renderProfile(id: String?) {
        webView.loadData("<h1>" + id + "</h1>", "text/html", "utf-8")
    }
}
