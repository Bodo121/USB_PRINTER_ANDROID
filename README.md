# DigitusPrint Android

Android PrintService prototype for the DIGITUS DA-70254 USB 2.0 network hub via its LPR/LPD print endpoint.

## Build
GitHub Actions builds a debug APK on every push to `main` and through manual workflow dispatch. Download it from the workflow run Artifacts section.

## Usage
Connect to the same LAN as the hub, enter its IP and printer LPR queue name, save, and enable Digitus Print in Android Printing settings.

**Important:** This first release forwards Android-generated PDF unchanged. Printing requires a printer with native PDF support; otherwise a printer-language converter/driver must be added. A successful LPR transfer does not guarantee physical printing. The app has not been tested against a physical DA-70254.
