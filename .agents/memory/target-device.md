---
name: Target device single
description: App ini hanya menarget satu perangkat. Jangan pertimbangkan device lain saat mengerjakan apapun.
---

## Target Device

- **Model:** Xiaomi Mi 9T / Redmi K20 (hardware identik, beda nama regional)
- **Chipset:** Qualcomm Snapdragon 730 (8 nm), Kryo 470 octa-core (2× 2.2 GHz Gold + 6× 1.8 GHz Silver)
- **GPU:** Adreno 618
- **RAM:** 6 GB
- **Storage:** 64 GB UFS 2.0 (sequential read ~1.2 GB/s) — **no microSD**
- **OS:** MIUI 12 berbasis Android 11
- **Layar:** 6.39" AMOLED, 1080×2340, ~403 ppi, Gorilla Glass 5 — full screen tanpa notch/punch-hole (kamera pop-up motorized)
- **Baterai:** 4000 mAh, 18W fast charge
- **Konektivitas:** USB-C 2.0, BT 5.0 (aptX), NFC, IR blaster, Wi-Fi ac dual-band

## Catatan Hardware Relevan untuk App

- **UFS 2.0** — I/O cukup kencang; artwork cache dan lyric cache tetap harus dikelola ketat karena tidak ada microSD (storage internal saja).
- **Adreno 618** — mampu menjalankan shader GLSL (fluid background), tapi tetap harus efisien; jangan render full-res tanpa FittedBox/downscale.
- **6 GB RAM** — Android 11 + MIUI 12 baseline ~2.5 GB; efektif tersisa ~3.5 GB untuk app; hindari operasi paralel berat atau cache besar-besaran.
- **AMOLED tanpa notch** — layar penuh bebas cutout; warna hitam benar-benar mati piksel (hemat baterai untuk dark theme).

## Aturan

Tidak ada rencana untuk mendukung perangkat lain. Saat mengerjakan apapun:

- **Jangan** tambahkan workaround, compat layer, atau fallback untuk device/OS lain.
- **Jangan** pertimbangkan ABI selain arm64-v8a (SD730 adalah ARM64).
- **Jangan** pertimbangkan Android versi lain — target adalah Android 11 / MIUI 12.
- **Jangan** buat kode yang "generik untuk semua device" jika ada solusi yang lebih optimal untuk SD730 + MIUI 12 spesifik.
- Saat audit/review kode, temuan tentang "tidak kompatibel dengan device X/Y" tidak relevan dan bisa diabaikan.

**Why:** User secara eksplisit meminta fokus single-device. Overhead compat multi-device hanya membuang resource dan kompleksitas tanpa manfaat.
