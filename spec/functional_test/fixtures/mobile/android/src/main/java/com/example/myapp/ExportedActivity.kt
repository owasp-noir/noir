package com.example.myapp

import android.app.Activity
import android.content.Intent
import android.os.Bundle

// Exported activity with no intent-filter. It is reachable only by an explicit
// intent naming the component, but it still reads attacker-controllable extras
// and forwards them, so the IPC surface is real and worth linking to code.
class ExportedActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val token = intent.getStringExtra("token")
        handleExplicitIntent(token)
    }

    private fun handleExplicitIntent(token: String?) {
        startActivity(Intent(this, NextActivity::class.java))
    }
}
