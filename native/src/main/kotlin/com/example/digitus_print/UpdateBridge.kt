// SPDX-License-Identifier: GPL-3.0-or-later
package com.example.digitus_print

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Public GitHub Releases updates. Installation ALWAYS needs Android user approval.
 * Do not distribute updates using one-off GitHub Actions debug signing certificates.
 */
class UpdateBridge(private val activity: Activity) {
    private val executor=Executors.newSingleThreadExecutor()
    private val api="https://api.github.com/repos/Bodo121/USB_PRINTER_ANDROID/releases/latest"
    private val host="github.com"
    private var downloaded: File? = null
    private var expectedDigest: String? = null
    private var pendingVersion: String? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger,"digitus_print/updates")
          .setMethodCallHandler { call, reply ->
            when(call.method) {
              "check" -> executor.execute {
                try {
                  val release=fetchRelease()
                  activity.runOnUiThread {reply.success(release)}
                } catch (e: Exception) {
                  activity.runOnUiThread { reply.error("UPDATE_CHECK",e.message ?: "Update check failed",null) }
                }
              }
              "download" -> {
                val url=call.argument<String>("url").orEmpty()
                val digest=call.argument<String>("digest").orEmpty()
                val version=call.argument<String>("version").orEmpty()
                executor.execute {
                  try {
                    val saved=downloadRelease(url,digest,version)
                    activity.runOnUiThread {reply.success(saved.length())}
                  } catch(e:Exception) {
                    activity.runOnUiThread {reply.error("UPDATE_DOWNLOAD",e.message ?: "Download failed",null)}
                  }
                }
              }
              "install" -> {
                try {reply.success(installDownloaded())}
                catch(e:Exception) {reply.error("UPDATE_INSTALL",e.message ?: "Cannot open installer",null)}
              }
              else -> reply.notImplemented()
            }
          }
    }

    private fun currentVersion(): String {
        @Suppress("DEPRECATION")
        val info=activity.packageManager.getPackageInfo(activity.packageName,0)
        return info.versionName ?: "0.0.0"
    }

    private fun https(uri: URL, allowAssetDomain: Boolean) {
        if(uri.protocol!="https")throw IOException("Only HTTPS is allowed for updates")
        val hostname=uri.host.lowercase()
        val valid=hostname=="api.github.com" ||
          (allowAssetDomain && (hostname=="github.com" ||
            hostname=="release-assets.githubusercontent.com" ||
            hostname=="objects.githubusercontent.com"))
        if(!valid)throw IOException("Untrusted update host: $hostname")
    }

    private fun connect(initial: URL, accept: String, allowAssetDomain:Boolean):HttpURLConnection {
        var current=initial
        repeat(6) {
          https(current,allowAssetDomain)
          val conn=(current.openConnection() as HttpURLConnection).apply{
            connectTimeout=12000
            readTimeout=25000
            instanceFollowRedirects=false
            setRequestProperty("User-Agent","DigitusPrint-Android-Updater")
            setRequestProperty("Accept",accept)
          }
          val code=conn.responseCode
          if(code in 300..399){
            val next=conn.getHeaderField("Location")
            conn.disconnect()
            if(next.isNullOrEmpty())throw IOException("Update server redirected without a location")
            current=URL(current,next)
          }else{
            if(code!=200){
              conn.disconnect()
              throw IOException("Update server returned HTTP $code")
            }
            return conn
          }
        }
        throw IOException("Update request redirected too many times")
    }

    private fun fetchRelease():Map<String,Any> {
        val conn=connect(URL(api),"application/vnd.github+json",false)
        try {
          val json=conn.inputStream.bufferedReader(Charsets.UTF_8).use {reader->
            val text=reader.readText()
            if(text.length>512_000)throw IOException("Unexpectedly large release metadata")
            JSONObject(text)
          }
          val tag=json.optString("tag_name")
          if(!tag.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+"))) {
            throw IOException("Release does not have a supported version tag")
          }
          val assets=json.optJSONArray("assets") ?: throw IOException("Release has no APK")
          var url=""
          var sha=""
          var size=0L
          for(i in 0 until assets.length()){
            val asset=assets.optJSONObject(i) ?: continue
            if(asset.optString("name")=="DigitusPrint.apk"){
              url=asset.optString("browser_download_url")
              sha=asset.optString("digest")
              size=asset.optLong("size")
              break
            }
          }
          if(url.isEmpty())throw IOException("Release APK missing. Maintainer must configure signed release publishing.")
          if(!sha.matches(Regex("sha256:[a-fA-F0-9]{64}")))throw IOException(
            "Release APK is missing a verifiable SHA-256 digest")
          if(size<=0L || size>200L*1024L*1024L)throw IOException("Invalid release APK size")
          val uri=URL(url)
          if(uri.host!="github.com" ||
             !uri.path.startsWith("/Bodo121/USB_PRINTER_ANDROID/releases/download/")) {
            throw IOException("APK URL does not match official project releases")
          }
          return mapOf("version" to tag.removePrefix("v"),
            "current" to currentVersion(),"url" to url,
            "digest" to sha,"size" to size,
            "notes" to json.optString("body").take(1200))
        } finally {conn.disconnect()}
    }

    private fun downloadRelease(url:String,digest:String,version:String):File {
        if(!digest.matches(Regex("sha256:[0-9a-fA-F]{64}"))) {
          throw IOException("A GitHub SHA-256 digest is required")
        }
        if(!version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+"))) {
          throw IOException("Invalid version")
        }
        val uri=URL(url)
        if(uri.protocol!="https"||uri.host!="github.com" ||
          !uri.path.matches(Regex(
            "/Bodo121/USB_PRINTER_ANDROID/releases/download/v[0-9]+\\.[0-9]+\\.[0-9]+/DigitusPrint\\.apk"))) {
          throw IOException("APK must come from this project's GitHub release")
        }
        if(!uri.path.contains("/v$version/"))throw IOException("Version and download URL differ")
        val root=activity.getExternalFilesDir(null) ?: throw IOException("No app update directory")
        val folder=File(root,"updates")
        if(!folder.exists()&&!folder.mkdirs())throw IOException("Could not create update directory")
        val output=File(folder,"DigitusPrint-update.apk")
        val temp=File(folder,"DigitusPrint-update.tmp")
        temp.delete()
        val connection=connect(uri,"application/octet-stream",true)
        val checksum=MessageDigest.getInstance("SHA-256")
        var transferred=0L
        try {
          connection.inputStream.use{input->
            FileOutputStream(temp).use{out->
              val buffer=ByteArray(32768)
              while(true){
                val read=input.read(buffer)
                if(read<0)break
                transferred+=read.toLong()
                if(transferred>200L*1024*1024)throw IOException("APK exceeds maximum size")
                checksum.update(buffer,0,read)
                out.write(buffer,0,read)
              }
              out.fd.sync()
            }
          }
          if(transferred<100_000)throw IOException("Downloaded file is not a valid APK size")
          val actual=checksum.digest().joinToString(""){"%02x".format(it)}
          if(!actual.equals(digest.substringAfter(":"),ignoreCase=true)) {
            throw IOException("APK SHA-256 mismatch; refusing installation")
          }
          if(output.exists()&&!output.delete())throw IOException("Cannot replace previous update")
          if(!temp.renameTo(output))throw IOException("Could not finalize APK download")
          downloaded=output
          expectedDigest=digest
          pendingVersion=version
          return output
        }catch(e:Exception){
          temp.delete()
          throw e
        }finally{connection.disconnect()}
    }

    private fun installDownloaded():String {
        val apk=downloaded ?: throw IOException("No verified APK downloaded")
        val digest=expectedDigest ?: throw IOException("No recorded APK checksum")
        if(!apk.exists()||apk.length()<100_000)throw IOException("Verified APK is missing")
        // Re-check the file between download and install.
        val check=MessageDigest.getInstance("SHA-256")
        FileInputStream(apk).use{input->
          val buf=ByteArray(32768)
          while(true){
            val n=input.read(buf)
            if(n<0)break
            check.update(buf,0,n)
          }
        }
        val actual=check.digest().joinToString(""){"%02x".format(it)}
        if(!actual.equals(digest.substringAfter(":"),ignoreCase=true)) {
          throw IOException("Downloaded APK changed; refusing installation")
        }
        if(Build.VERSION.SDK_INT>=26 &&
          !activity.packageManager.canRequestPackageInstalls()){
          activity.startActivity(Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}")
          ))
          return "permission_required"
        }
        val content=FileProvider.getUriForFile(activity,
            "${activity.packageName}.updates",apk)
        val intent=Intent(Intent.ACTION_VIEW).apply{
            setDataAndType(content,"application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
        return "installer_opened"
    }

    fun close() {executor.shutdown()}
}
