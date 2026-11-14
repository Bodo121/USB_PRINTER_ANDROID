package com.example.digitusprint;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.ViewGroup;
import android.widget.*;
import java.net.*;

public final class MainActivity extends Activity {
    private EditText host, queue, name;
    private TextView status;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setPadding(32, 32, 32, 32);
        ScrollView scroller = new ScrollView(this); scroller.addView(root); setContentView(scroller);
        TextView title = new TextView(this); title.setText("DIGITUS DA-70254 · Network Print"); title.setTextSize(22); root.addView(title);
        TextView note = new TextView(this); note.setText("LPR port 515. Your printer must understand PDF for direct printing. Find the queue name in Windows DIGITUS Device Properties."); root.addView(note);
        host = field(root, "Hub IP / hostname", HubConfig.host(this));
        queue = field(root, "LPR queue name (exact)", HubConfig.queue(this));
        name = field(root, "Printer display name", HubConfig.printerName(this));
        button(root, "Save printer", () -> {
            if (host.getText().toString().trim().isEmpty() || queue.getText().toString().trim().isEmpty()) { status.setText("Enter both hub IP and queue name."); return; }
            HubConfig.save(this, host.getText().toString(), queue.getText().toString(), name.getText().toString());
            status.setText("Saved. If print service was enabled, disable and re-enable it to refresh the printer.");
        });
        button(root, "Test TCP 515", () -> {
            String h = host.getText().toString().trim(); status.setText("Testing " + h + ":515...");
            new Thread(() -> {
                String result;
                try (Socket socket = new Socket()) { socket.connect(new InetSocketAddress(h, 515), 4000); result = "Connected to LPR port 515."; }
                catch (Exception e) { result = "Connection failed: " + e.getMessage(); }
                final String msg = result; runOnUiThread(() -> status.setText(msg));
            }).start();
        });
        button(root, "Android printing settings", () -> startActivity(new Intent(Settings.ACTION_PRINT_SETTINGS)));
        status = new TextView(this); status.setText("Enable Digitus Print in Android Printing settings, then Print from another app."); root.addView(status);
    }
    private EditText field(LinearLayout layout, String hint, String value) {
        EditText edit = new EditText(this); edit.setSingleLine(true); edit.setHint(hint); edit.setText(value); layout.addView(edit, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)); return edit;
    }
    private void button(LinearLayout layout, String label, Runnable click) {
        Button b = new Button(this); b.setText(label); b.setOnClickListener(v -> click.run()); layout.addView(b);
    }
}
