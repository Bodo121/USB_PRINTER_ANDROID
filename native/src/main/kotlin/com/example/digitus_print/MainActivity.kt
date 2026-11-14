// SPDX-License-Identifier: GPL-3.0-or-later
package com.example.digitus_print

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.github.noble6.canonivec.PageRenderer
import io.github.noble6.canonivec.core.IvecPrintJob
import io.github.noble6.canonivec.core.JobSettings
import io.github.noble6.canonivec.core.ModelDatabase
import io.github.noble6.canonivec.core.Quality
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.Executors

/** Native Canon raster preparation for the experimental NU transport. */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var updateBridge: UpdateBridge? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        updateBridge = UpdateBridge(this).also { it.register(engine) }
        MethodChannel(engine.dartExecutor.binaryMessenger, "digitus_print/canon").setMethodCallHandler { call, reply ->
            if (call.method != "prepareRaster") {
                reply.notImplemented()
                return@setMethodCallHandler
            }
            val pdf = call.argument<ByteArray>("pdf")
            val approved = call.argument<Boolean>("approved") == true
            val gray = call.argument<Boolean>("gray") == true
            if (!approved || pdf == null || pdf.isEmpty()) {
                reply.error("CONFIRMATION", "Explicit test consent and a PDF are required", null)
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val result = convertRaster(pdf, gray)
                    runOnUiThread { reply.success(result) }
                } catch (ex: Exception) {
                    runOnUiThread { reply.error("PRINT_FAILED", ex.message ?: ex.javaClass.simpleName, null) }
                }
            }
        }
    }

    private fun convertRaster(pdfData: ByteArray, gray: Boolean): ByteArray {
        val input = File.createTempFile("canon-source", ".pdf", cacheDir)
        val output = File.createTempFile("canon-ivec", ".bin", cacheDir)
        try {
            input.writeBytes(pdfData)
            val database = ModelDatabase.parse(assets.open("ivec_models.json").bufferedReader().use { it.readText() })
            val profile = database.byId("canong2020") ?: throw IOException("Bundled Canon G2020 profile missing")
            val media = profile.media("plain") ?: profile.defaultMediaType()
            val paper = profile.size("A4") ?: profile.defaultPaper()
            val settings = JobSettings(paper, media, gray = gray, quality = Quality.NORMAL, uuid = UUID.randomUUID().toString())
            val job = IvecPrintJob(profile, settings, hostEnv = "android")
            ParcelFileDescriptor.open(input, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { renderer ->
                    if (renderer.pageCount < 1) throw IOException("PDF contains no pages")
                    // Deliberately one page until the G2420 profile is proven on physical hardware.
                    val page = PageRenderer(renderer, job)
                    try { page.addPage(0, 1) { false } }
                    finally { page.recycle() }
                }
            }
            FileOutputStream(output).use { job.writeTo(it) }
            if (output.length() == 0L || output.length() > 100L * 1024L * 1024L) {
                throw IOException("Invalid or oversized Canon raster stream")
            }
            return output.readBytes()
        } finally {
            input.delete()
            output.delete()
        }
    }

    // Prefer the existing native-resolution high-refresh mode without forcing
    // lower resolution, unrelated modes or a refresh unsupported by the panel.
    private fun preferHighRefreshRate() {
        if (android.os.Build.VERSION.SDK_INT < 23) return
        try {
            val display = window.decorView.display ?: return
            val current = display.mode
            val best = display.supportedModes
                .filter { it.physicalWidth == current.physicalWidth &&
                          it.physicalHeight == current.physicalHeight }
                .maxByOrNull { it.refreshRate } ?: return
            if (best.refreshRate > current.refreshRate + 0.5f) {
                val params = window.attributes
                params.preferredDisplayModeId = best.modeId
                window.attributes = params
            }
        } catch (_: Exception) {
            // Adaptive display scheduling still works when the hint is ignored.
        }
    }

    override fun onResume() {
        super.onResume()
        preferHighRefreshRate()
    }

    override fun onDestroy() {
        updateBridge?.close()
        worker.shutdown()
        super.onDestroy()
    }
}
