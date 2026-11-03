package com.example.electrowave_mobile

import android.app.Application
import java.io.File

class ElectrowaveApplication:Application() {
    override fun onCreate() {
        super.onCreate()
        val previous=Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler {thread,error ->
            try {
                val file=File(filesDir,"native-crash.log")
                if(file.exists() && file.length()>262144) {
                    val older=File(filesDir,"native-crash.log.previous")
                    older.delete();file.renameTo(older)
                }
                file.appendText("${java.util.Date()} ${thread.name}\n${error.stackTraceToString().take(24576)}\n")
            } catch(_:Throwable) {}
            previous?.uncaughtException(thread,error)
        }
    }
}
