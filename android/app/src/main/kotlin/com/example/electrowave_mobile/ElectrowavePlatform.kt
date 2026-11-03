package com.example.electrowave_mobile

import android.app.Activity
import android.app.job.*
import android.content.*
import android.content.pm.*
import android.graphics.drawable.Icon
import android.media.*
import android.net.Uri
import android.os.*
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class ElectrowavePlatform(private val activity: MainActivity, private val channel:MethodChannel) {
    private var folderResult:MethodChannel.Result?=null
    private val executor=Executors.newSingleThreadExecutor()
    init {
        channel.setMethodCallHandler { call,result ->
            try { when(call.method) {
                "version" -> result.success(activity.packageManager.getPackageInfo(activity.packageName,0).versionName)
                "takeAction" -> { result.success(activity.intent?.getStringExtra("electrowave_action"));activity.intent?.removeExtra("electrowave_action") }
                "shortcuts" -> { shortcuts();result.success(null) }
                "output" -> {
                    val audio=activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val devices=audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    result.success(when { devices.any{it.type==AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type==26 || it.type==27}->"bluetooth"
                        devices.any{it.type in intArrayOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES,AudioDeviceInfo.TYPE_WIRED_HEADSET,AudioDeviceInfo.TYPE_USB_HEADSET)}->"headphones"
                        else->"speaker" })
                }
                "pickBackupFolder" -> {
                    check(folderResult==null) {"Folder picker already open"};folderResult=result
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION),8201)
                }
                "configureBackups" -> {
                    val uri=call.argument<String>("uri")
                    val prefs=activity.getSharedPreferences("electrowave_backup",0)
                    val previous=prefs.getString("uri",null)
                    prefs.edit().putString("uri",uri).apply()
                    val scheduler=activity.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
                    if(uri!=null && previous==uri && scheduler.allPendingJobs.any{it.id==8202}) {result.success(null);return@setMethodCallHandler}
                    scheduler.cancel(8202)
                    if(uri!=null) scheduler.schedule(JobInfo.Builder(8202,ComponentName(activity,BackupJob::class.java)).setPeriodic(7*24*60*60*1000L).setPersisted(true).build())
                    result.success(null)
                }
                "writeBackup" -> { val bytes=call.argument<ByteArray>("bytes")!!;val uri=call.argument<String>("uri")!!
                    executor.execute { try { BackupFiles.write(activity,uri,bytes);activity.runOnUiThread{result.success(null)} } catch(e:Exception){activity.runOnUiThread{result.error("backup",e.message,null)}} }
                }
                "crossfeedFile" -> {val path=call.argument<String>("path")!!
                    executor.execute {try{val rendered=AudioAnalysis.crossfeed(path,File(activity.cacheDir,"crossfeed"),call.argument<Boolean>("mix") ?: true);activity.runOnUiThread{result.success(rendered)}}catch(e:Exception){activity.runOnUiThread{result.error("crossfeed",e.message,null)}}}
                }
                "analyze" -> { val path=call.argument<String>("path")!!
                    executor.execute { try { val data=AudioAnalysis.analyze(path);activity.runOnUiThread{result.success(data)} } catch(e:Exception){activity.runOnUiThread{result.error("decode",e.message,null)}} }
                }
                else -> result.notImplemented()
            } } catch(e:Exception) { result.error("platform",e.message,null) }
        }
    }
    fun activityResult(request:Int,code:Int,data:Intent?):Boolean {
        if(request!=8201) return false
        val result=folderResult;folderResult=null
        val uri=data?.data
        if(code!=Activity.RESULT_OK || uri==null) {result?.success(null);return true}
        try {
            activity.contentResolver.takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            result?.success(uri.toString())
        } catch(e:Exception) { result?.error("folder",e.message,null) }
        return true
    }
    private fun shortcuts() {
        if(Build.VERSION.SDK_INT<25) return
        val manager=activity.getSystemService(ShortcutManager::class.java)
        manager.dynamicShortcuts=listOf("shuffle" to "Shuffle all","resume" to "Resume","favorites" to "Favourites").map { (action,label) ->
            ShortcutInfo.Builder(activity,action).setShortLabel(label).setIcon(Icon.createWithResource(activity,R.drawable.ic_stat_electrowave))
                .setIntent(Intent(activity,MainActivity::class.java).setAction(Intent.ACTION_VIEW).putExtra("electrowave_action",action)).build()
        }
    }
}

object BackupFiles {
    fun write(context:Context,tree:String,bytes:ByteArray) {
        val resolver=context.contentResolver;val root=Uri.parse(tree)
        val parent=DocumentsContract.buildDocumentUriUsingTree(root,DocumentsContract.getTreeDocumentId(root))
        val name="electrowave-auto-${System.currentTimeMillis()}.ewbackup"
        val uri=DocumentsContract.createDocument(resolver,parent,"application/octet-stream","$name.tmp") ?: error("Cannot create backup")
        try {
            resolver.openOutputStream(uri,"wt")!!.use{it.write(bytes);it.flush()}
            DocumentsContract.renameDocument(resolver,uri,name) ?: error("Cannot finish backup")
        } catch(e:Exception) { try{DocumentsContract.deleteDocument(resolver,uri)}catch(_:Exception){};throw e }
        val children=DocumentsContract.buildChildDocumentsUriUsingTree(root,DocumentsContract.getTreeDocumentId(root))
        val entries=ArrayList<Pair<String,String>>()
        resolver.query(children,arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME),null,null,null)?.use { c ->
            while(c.moveToNext()) {val n=c.getString(1);if(n.startsWith("electrowave-auto-") && n.endsWith(".ewbackup")) entries.add(n to c.getString(0))}
        }
        for(entry in entries.sortedByDescending{it.first}.drop(5)) DocumentsContract.deleteDocument(resolver,DocumentsContract.buildDocumentUriUsingTree(root,entry.second))
    }
}

/** Boots only the offline backup entry point; playback is never started here. */
class BackupJob:JobService() {
    private var engine:FlutterEngine?=null
    override fun onStartJob(params:JobParameters):Boolean {
        val loader=FlutterInjector.instance().flutterLoader();loader.startInitialization(this);loader.ensureInitializationComplete(this,null)
        val worker=FlutterEngine(this);engine=worker
        MethodChannel(worker.dartExecutor.binaryMessenger,"electrowave/backup_worker").setMethodCallHandler { call,result ->
            when(call.method) {
                "config" -> result.success(getSharedPreferences("electrowave_backup",0).getString("uri",null))
                "write" -> try { BackupFiles.write(this,call.argument<String>("uri")!!,call.argument<ByteArray>("bytes")!!);result.success(null) } catch(e:Exception){ result.error("backup",e.message,null) }
                "finished" -> {result.success(null);Handler(mainLooper).post{jobFinished(params,call.arguments==false);worker.destroy();engine=null}}
                else->result.notImplemented()
            }
        }
        worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"backupWorker"))
        return true
    }
    override fun onStopJob(params:JobParameters):Boolean {engine?.destroy();engine=null;return true}
}
