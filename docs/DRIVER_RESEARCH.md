# Native Android translation layer research

Hardware: **DIGITUS DA-70254 USB-over-IP four-port hub** and **Canon PIXMA G2420**.

## Confirmed

1. The DIGITUS manual specifies ordinary LPR printing (TCP/515). The printer queue name can be displayed in the DIGITUS Windows setup utility, but Windows is NOT needed at runtime for LPR.
2. Canon's Windows driver converts rendered documents into Canon-specific instructions. These cannot be reproduced by transferring PDF bytes as-is.
3. Canon distributes `cnijfilter2-source-6.10-1.tar.gz` for the **G2020** series. Do not assume G2420 model identification/profiles are identical without probing.
4. An independent GPL-3.0 Canon IVEC driver exists: https://github.com/noble6/canon-universal-driver . Its **Android USB implementation** runs natively without Windows. The G2020 has an IVEC profile; **G2420 is not specifically listed**. Its renderer, PWG raster formatting and IVEC command serialization are useful reference implementations. Respect GPL-3.0 licensing if porting code.

## Android implementation layers

```
Material 3 Flutter UI
  -> file selection / PDF render / page selection
  -> device profile + Canon raster/IVEC conversion (NOT IMPLEMENTED)
  -> LPR transport (lib/services/lpr_transport.dart: IMPLEMENTED)
  -> DIGITUS DA-70254 queue, port 515
  -> Canon G2420 USB endpoint (through hub firmware)
```

The LPR sender works only for **already printer-ready** data. It does not mean the actual printer accepts the stream, and acceptance by the hub does not prove a sheet printed.

## Necessary verification before printing

- Discover the hub IP and its actual LPR queue name using Windows once or device web interface if shown.
- Confirm whether G2420 identifies as G2020 series, and which Canon USB device ID / protocol it advertises.
- Compare a Windows driver RAW spool capture with Canon G2020 IVEC examples, ideally one-page draft black, one-page A4 color.
- Find whether DIGITUS LPR forwards binary IVEC transparently to the printer. If it does not, implement its USB-over-IP device protocol (not documented in public manual) rather than assuming USB/IP standard.
- Implement or adapt raster encoding and Canon job envelope. Add 1-page test print before color, quality and maintenance features.
- Maintenance/status/scanning need bidirectional USB access. LPR usually doesn't expose return USB endpoints; do not claim these features work until USB-over-IP control protocol is implemented and tested.

## Driver sources

- https://ftp.assmann.com/pub/DA-/DA-70254___4016032390091/DA-70254_manual_English_20170126.pdf
- https://asia.canon/en/support/0101091901 (Canon binary Linux G2020 family)
- https://hk.canon/en/support/0101092101?model=G2020 (Canon Linux source archive)
- https://github.com/noble6/canon-universal-driver (GPL-3.0+ driver, IVEC, Android PrintService)

## Status

A native Dart LPR/LPD transport with acknowledgement validation and queue inquiry has been added. Direct Canon printer-language conversion is **not implemented** and must remain disabled in production until hardware confirmation.

No Windows application, Windows driver, or external print server is needed to run the network transport itself.
