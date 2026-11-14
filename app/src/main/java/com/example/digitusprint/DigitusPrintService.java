package com.example.digitusprint;

import android.print.*;
import android.printservice.*;
import android.os.ParcelFileDescriptor;
import java.io.*;
import java.util.List;

public final class DigitusPrintService extends PrintService {
    @Override protected PrinterDiscoverySession onCreatePrinterDiscoverySession() { return new Session(); }
    @Override protected void onRequestCancelPrintJob(PrintJob job) { job.cancel(); }
    @Override protected void onPrintJobQueued(PrintJob job) {
        if (!job.start()) return;
        String host = HubConfig.host(this), queue = HubConfig.queue(this);
        if (host.isEmpty() || queue.isEmpty()) { job.fail("Configure hub IP and LPR queue in Digitus Print"); return; }
        new Thread(() -> {
            ParcelFileDescriptor fd = job.getDocument().getData();
            if (fd == null) { job.fail("No print document"); return; }
            try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(fd)) {
                LprClient.send(host, queue, input);
                job.complete();
            } catch (Exception e) { job.fail("LPR: " + e.getMessage()); }
        }, "digitus-lpr").start();
    }
    private final class Session extends PrinterDiscoverySession {
        @Override public void onStartPrinterDiscovery(List<PrinterId> priorityList) { refresh(); }
        @Override public void onStopPrinterDiscovery() { }
        @Override public void onValidatePrinters(List<PrinterId> ids) { refresh(); }
        @Override public void onStartPrinterStateTracking(PrinterId printerId) { refresh(); }
        @Override public void onStopPrinterStateTracking(PrinterId printerId) { }
        @Override public void onDestroy() { }
        private void refresh() {
            if (HubConfig.host(DigitusPrintService.this).isEmpty() || HubConfig.queue(DigitusPrintService.this).isEmpty()) return;
            PrinterId id = generatePrinterId("digitus-lpr");
            PrinterCapabilitiesInfo cap = new PrinterCapabilitiesInfo.Builder(id)
                .addMediaSize(PrintAttributes.MediaSize.ISO_A4, true)
                .addMediaSize(PrintAttributes.MediaSize.NA_LETTER, false)
                .addResolution(new PrintAttributes.Resolution("300", "300 dpi", 300, 300), true)
                .setColorModes(PrintAttributes.COLOR_MODE_MONOCHROME | PrintAttributes.COLOR_MODE_COLOR, PrintAttributes.COLOR_MODE_COLOR)
                .build();
            PrinterInfo info = new PrinterInfo.Builder(id, HubConfig.printerName(DigitusPrintService.this), PrinterInfo.STATUS_IDLE)
                .setCapabilities(cap).build();
            addPrinters(java.util.Collections.singletonList(info));
        }
    }
}
