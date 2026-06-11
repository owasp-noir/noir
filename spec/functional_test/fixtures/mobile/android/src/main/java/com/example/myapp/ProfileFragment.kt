package com.example.myapp

import android.os.Bundle
import android.view.View
import androidx.fragment.app.Fragment

class ProfileFragment : Fragment() {

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val userId = arguments?.getString("userId")
        val ref = activity?.intent?.data?.getQueryParameter("ref")
        loadProfile(userId, ref)
    }

    private fun loadProfile(userId: String?, ref: String?) {
        // render the profile for the deep-linked user
    }
}
