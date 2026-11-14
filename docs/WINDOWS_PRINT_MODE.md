# Printing through the user's Windows PC and DIGITUS DA-70251

## Why this mode works differently

This mode uses the existing Windows Canon printer driver and the
DIGITUS virtual USB driver. Android sends the original PDF to a
locally-running Windows companion server, which invokes SumatraPDF
against the already-working Windows printer queue.

  Android Digitus Print (PDF)
    -> HTTP + token to Windows PC on trusted LAN
    -> Python bridge -> SumatraPDF named print queue
    -> official Windows Canon driver
    -> official DIGITUS virtual USB driver -> DA-70251 -> Canon

It does NOT make the native Android USB-over-IP (UNT$) implementation
complete. Android does not replay undocumented 383-byte USB messages.

## Requirements

The Windows PC that previously printed through DIGITUS must stay
powered on with the official USB Server client connected. Install
Python 3.10+ and SumatraPDF. Download the separate ZIP companion
named DigitusPrint-WindowsBridge-v1.0.zip supplied along with this
APK. It contains bridge.py, start_bridge.bat, README.md and tests.

## Setup steps

1. On the Windows PC, confirm printing to the Canon queue already works.
2. In PowerShell run Get-Printer | Select Name and note its exact name.
3. Extract the companion ZIP; launch start_bridge.bat; supply the
   printer queue name (often Canon G2010 series). Or run:
   py -3 bridge.py --host 0.0.0.0 --port 8765 --printer "Canon G2010 series"
4. The Windows console prints a long pairing token. Leave it running.
   Allow inbound Python only on Windows Private-network firewall.
   Never expose TCP 8765 to the Internet or untrusted Wi-Fi.
5. Run ipconfig to get the Windows computer's current IPv4 address.
   The Windows PC in the original capture was 192.168.0.117,
   while the DA-70251 hub was 192.168.0.74. These may change.
6. On Android, open Print, choose a PDF or create a one-page test.
   In Print using Windows PC enter the PC IP (NOT the hub IP),
   port 8765, and the token. Check Windows bridge first.
7. Tap Send PDF via Windows, then Check last job for status.

## Security and reliability

The bridge authenticates every request with a random 256-bit secret,
rejects internet clients, restricts uploads to PDFs under 25 MiB,
does not execute request-controlled shell commands, and prevents
double printing by persisting per-job idempotency IDs and PDF hashes.
Interrupted jobs after a server restart become uncertain, not
automatically resent. The Android app also blocks new print attempts
after uncertain delivery until the user explicitly checks the Windows
queue and printer. This is local HTTP, NOT TLS. Only use a trusted LAN
and keep your pairing token private. The token is saved in app-private
preferences for convenience; users of rooted phones should protect
device storage.

SumatraPDF returning success means a job was submitted to the Windows
spooler, not that paper has emerged from the printer. Offline bridge
tests cover authentication, idempotency, invalid PDF handling and
restart safety. They cannot validate physical paper output.

## Source references

- Actual DA-70251 USB sharing manual:
  https://www.manualslib.com/manual/777922/Digitus-Da-70251.html
- Supported SumatraPDF command-line printing:
  https://www.sumatrapdfreader.org/docs/Command-line-arguments

Native Android-to-DIGITUS printing without Windows still requires
a complete Canon USB command generator and stateful NU transport.
See NU_IDA_DRIVER_ANALYSIS.md for details.
