package com.example.digitusprint;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

/** RFC 1179 LPR print transfer. Does not convert PDF to a printer-specific format. */
final class LprClient {
    private static void ok(InputStream input) throws IOException {
        int response = input.read();
        if (response != 0) throw new IOException("LPD rejected command; response=" + response);
    }
    private static void command(OutputStream out, int code, String data) throws IOException {
        out.write(code); out.write(data.getBytes(StandardCharsets.US_ASCII)); out.write('\n'); out.flush();
    }
    static void send(String host, String queue, InputStream document) throws IOException {
        if (!host.matches("[A-Za-z0-9.:-]{1,253}") || queue.isEmpty() || !queue.matches("[!-~]{1,100}"))
            throw new IOException("Invalid host or LPR queue name");
        File file = File.createTempFile("digitus-print-", ".pdf");
        try {
            try (OutputStream tmp = new FileOutputStream(file)) {
                byte[] buf = new byte[16384]; int n;
                while ((n = document.read(buf)) != -1) tmp.write(buf, 0, n);
            }
            if (file.length() == 0) throw new IOException("Empty print job");
            String job = String.format(java.util.Locale.US, "%03d", (System.currentTimeMillis() / 1000) % 1000);
            String df = "dfA" + job + "android";
            String cf = "cfA" + job + "android";
            byte[] control = ("Handroid\nPandroid\nJAndroid document\nl" + df + "\nU" + df + "\nNdocument.pdf\n").getBytes(StandardCharsets.US_ASCII);
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress(host, 515), 6000);
                socket.setSoTimeout(10000);
                InputStream in = socket.getInputStream(); OutputStream out = socket.getOutputStream();
                command(out, 2, queue); ok(in);
                command(out, 2, control.length + " " + cf); ok(in);
                out.write(control); out.write(0); out.flush(); ok(in);
                command(out, 3, file.length() + " " + df); ok(in);
                try (InputStream f = new FileInputStream(file)) {
                    byte[] b = new byte[16384]; int n;
                    while ((n = f.read(b)) != -1) out.write(b, 0, n);
                }
                out.write(0); out.flush(); ok(in);
            }
        } finally { file.delete(); }
    }
}
