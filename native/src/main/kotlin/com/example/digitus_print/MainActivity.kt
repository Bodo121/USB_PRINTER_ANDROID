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

/** Native Canon raster conversion + LPR delivery; does NOT use Windows or CUPS. */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "digitus_print/canon").setMethodCallHandler { call, reply ->
            if (call.method != "experimentalPrint") {
                reply.notImplemented()
                return@setMethodCallHandler
            }
            val pdf = call.argument<ByteArray>("pdf")
            val host = call.argument<String>("host")?.trim().orEmpty()
            val queue = call.argument<String>("queue")?.trim().orEmpty()
            val approved = call.argument<Boolean>("approved") == true
            val gray = call.argument<Boolean>("gray") == true
            val dataFirst = call.argument<Boolean>("dataFirst") == true
            if (!approved || pdf == null || pdf.isEmpty()) {
                reply.error("CONFIRMATION", "Explicit test consent and a PDF are required", null)
                return@setMethodCallHandler
            }
            if (!host.matches(Regex("[0-9A-Za-z.:_-]{1,253}")) ||
                !queue.matches(Regex("[0-9A-Za-z_.-]{1,80}"))) {
                reply.error("SETTINGS", "Invalid hub host or LPR queue", null)
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val result = convertAndSend(pdf, host, queue, gray, dataFirst)
                    runOnUiThread { reply.success(result) }
                } catch (ex: Exception) {
                    runOnUiThread { reply.error("PRINT_FAILED", ex.message ?: ex.javaClass.simpleName, null) }
                }
            }
        }
    }

    private fun convertAndSend(pdfData: ByteArray, host: String, queue: String, gray: Boolean, dataFirst: Boolean): String {
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
            val diagnostics = sendLpr(host, queue, output, dataFirst)
            // Only a successful LPR transaction, NOT physical printer output.
            return "LPR TRANSPORT ACCEPTED (physical output unverified). " +
                "Queue: $queue | Raster bytes: ${output.length()} | " +
                diagnostics.joinToString(" | ") +
                ". Check the Canon G2420 for actual paper output."
        } finally {
            input.delete()
            output.delete()
        }
    }

    /** RFC 1179 receive-job transaction, with 1-byte acknowledgement after each stage. */
    private fun sendLpr(host: String, queue: String, raster: File, dataFirst: Boolean): List<String> {
        val stages = mutableListOf<String>()
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, 515), 8000)
            socket.soTimeout = 15000
            val stream = socket.getOutputStream()
            val input = socket.getInputStream()
            fun sendCommand(code: Int, text: String) {
                stream.write(code)
                stream.write((text + "\n").toByteArray(StandardCharsets.US_ASCII))
                stream.flush()
            }
            fun check(stage: String) {
                val code = try {
                    input.read()
                } catch (ex: java.net.SocketTimeoutException) {
                    throw IOException(
                        "LPR timeout awaiting $stage ACK; completed: ${stages.joinToString(", ")}",
                        ex
                    )
                }
                if (code < 0) throw IOException(
                    "LPR closed before $stage ACK; completed: ${stages.joinToString(", ")}"
                )
                if (code != 0) throw IOException(
                    "LPR rejected $stage (code $code); completed: ${stages.joinToString(", ")}"
                )
                stages.add("$stage: ACK 0")
            }
            val jobNum = ((System.currentTimeMillis() / 1000) % 1000).toString().padStart(3, '0')
            val df = "dfA${jobNum}android"
            val cf = "cfA${jobNum}android"
            val control = ("Handroid\nPandroid\nJCanon test\nl$df\nU$df\nNCanon-test\n")
                .toByteArray(StandardCharsets.US_ASCII)
            stages.add("source TCP port: ${socket.localPort}")
            sendCommand(2, queue); check("queue")
            fun sendControl() {
                sendCommand(2, "${control.size} $cf"); check("control header")
                stream.write(control); stream.write(0); stream.flush()
                check("control data")
            }
            fun sendData() {
                sendCommand(3, "${raster.length()} $df"); check("raster header")
                FileInputStream(raster).use { it.copyTo(stream, 32768) }
                stream.write(0); stream.flush()
                check("raster data")
            }
            // Never retry or switch ordering automatically. The user explicitly
            // selects data-first in the test UI to avoid duplicate print jobs.
            if (dataFirst) {
                sendData()
                sendControl()
            } else {
                sendControl()
                sendData()
            }
        }
        return stages
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
        worker.shutdown()
        super.onDestroy()
    }
}
