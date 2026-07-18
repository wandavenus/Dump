---
name: Target device single
description: App ini hanya menarget satu perangkat. Jangan pertimbangkan device lain saat mengerjakan apapun.
---

## Target Device

- **Model:** Xiaomi Mi 9T / Redmi K20 (hardware identik, beda nama regional)
- **Chipset:** Qualcomm Snapdragon 730 (Kryo 470, octa-core, ~2.2 GHz)
- **RAM:** 6 GB
- **Storage:** 64 GB
- **OS:** MIUI 12 berbasis Android 11

## Aturan

Tidak ada rencana untuk mendukung perangkat lain. Saat mengerjakan apapun:

- **Jangan** tambahkan workaround, compat layer, atau fallback untuk device/OS lain.
- **Jangan** pertimbangkan ABI selain arm64-v8a (SD730 adalah ARM64).
- **Jangan** pertimbangkan Android versi lain — target adalah Android 11 / MIUI 12.
- **Jangan** buat kode yang "generik untuk semua device" jika ada solusi yang lebih optimal untuk SD730 + MIUI 12 spesifik.
- Saat audit/review kode, temuan tentang "tidak kompatibel dengan device X/Y" tidak relevan dan bisa diabaikan.

**Why:** User secara eksplisit meminta fokus single-device. Overhead compat multi-device hanya membuang resource dan kompleksitas tanpa manfaat.
