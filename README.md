# Digitus Print · Flutter Material 3

Features: local LAN discovery of TCP/515 LPR candidates, saved IP and queue name, PDF/JPG/PNG/TXT selection, PDF preview, conversion of images and text to PDF, dark theme, and Android print dialog. GitHub Actions builds an installable debug APK.

**Canon PIXMA G2420:** This USB-only printer needs model-compatible Canon raster commands. Raw PDF-to-LPR does not reliably work and has deliberately not been enabled. Android's print dialog works only with a compatible Android print service or bridge, which this build does not provide. Detected TCP/515 hosts are not necessarily DIGITUS devices. A queue name may have to be copied from the Windows DIGITUS utility > Device Properties.

The app is a Flutter user interface and document-preparation prototype, **not yet a driver**. The Activity tab tracks print-dialog launches, not printed pages.

Actions > Flutter Material 3 APK > successful run > Artifacts to download the debug APK.

Local build: `flutter create . --platforms android --project-name digitus_print && flutter pub get && flutter build apk --debug`
