# Digitus Print · Flutter Material 3

Features: local LAN discovery of TCP/515 LPR candidates, saved IP and queue name, PDF/JPG/PNG/TXT selection, PDF preview, conversion of images and text to PDF, dark theme, and Android print dialog. GitHub Actions builds an installable debug APK.

**Canon PIXMA G2420:** This USB-only printer needs model-compatible Canon raster commands. Raw PDF-to-LPR does not reliably work and has deliberately not been enabled. Android's print dialog works only with a compatible Android print service or bridge, which this build does not provide. Detected TCP/515 hosts are not necessarily DIGITUS devices. A queue name may have to be copied from the Windows DIGITUS utility > Device Properties.

The app is a Flutter user interface and document-preparation prototype, **not yet a driver**. The Activity tab tracks print-dialog launches, not printed pages.

Actions > Flutter Material 3 APK > successful run > Artifacts to download the debug APK.

Local build: `flutter create . --platforms android --project-name digitus_print && flutter pub get && flutter build apk --debug`

## Experimental native Canon test (v0.3)

The Android Kotlin bridge includes a GPL-3.0-or-later-licensed IVEC/PWG Raster serializer, adapted from [noble6/canon-universal-driver](https://github.com/noble6/canon-universal-driver); the full original license is in `LICENSE`. It uses the G2020 profile as an **unverified candidate** for the Canon G2420. The first PDF page is rendered in Android PdfRenderer bands, encoded as Canon IVEC commands + PWG raster, and transmitted with RFC1179 LPR acknowledgements over port 515.

No Windows runtime, cloud server or external print bridge is used. **The Canon G2420 model/profile match and binary forwarding by DA-70254 have not been tested with physical hardware.** Only a one-page user-confirmed experiment is exposed. The app cannot receive USB printer status or confirm page output via one-way LPR. Do not attempt nozzle cleaning, ink flushing, or scan operations until the bidirectional USB protocol is properly identified.

`native/src/main` is copied into the Flutter Android app during CI. The repository is released under GPL-3.0-or-later due to the included Canon driver implementation. Copyright remains with the upstream contributors for adapted files. See `docs/DRIVER_RESEARCH.md`.
