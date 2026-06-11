package com.example.myapp

import android.app.Activity
import android.os.Bundle

class AliasTargetActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val token = intent.getStringExtra("aliasToken")
        dispatchAlias(token)
    }

    private fun dispatchAlias(token: String?) {
        // route alias traffic into the normal handler stack
    }
}
