package com.example.digitusprint;

import android.content.Context;
import android.content.SharedPreferences;

final class HubConfig {
    private static final String FILE = "hub";
    static String host(Context ctx) { return prefs(ctx).getString("host", ""); }
    static String queue(Context ctx) { return prefs(ctx).getString("queue", ""); }
    static String printerName(Context ctx) { return prefs(ctx).getString("printer", "DIGITUS LPR Printer"); }
    static void save(Context ctx, String host, String queue, String name) {
        prefs(ctx).edit().putString("host", host.trim()).putString("queue", queue.trim()).putString("printer", name.trim()).apply();
    }
    private static SharedPreferences prefs(Context ctx) { return ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE); }
}
