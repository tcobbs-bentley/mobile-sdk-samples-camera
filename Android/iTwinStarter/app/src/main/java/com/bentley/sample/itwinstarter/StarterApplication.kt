package com.bentley.sample.itwinstarter

import android.app.Application
import android.content.Context

class StarterApplication: Application() {
    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
        application = this
    }

    companion object {
        private lateinit var appContext: Context
        private lateinit var application: Application

        fun getContext() : Context {
            return appContext
        }
    }
}