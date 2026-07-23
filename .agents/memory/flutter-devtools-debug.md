---
name: Flutter DevTools debug workflow
description: Cara menjalankan Flutter debug web dan DevTools di Replit, serta batasan web-server.
---

# Flutter DevTools debug workflow

Workflow `Flutter Debug Web` menjalankan `flutter run -d web-server` di port 5173, sedangkan `Flutter DevTools` melayani DevTools di port 9100. Keduanya disimpan sebagai workflow manual dan tidak dijalankan otomatis oleh tombol `Project`.

**Why:** Environment ini tidak memiliki Chrome atau Android emulator, tetapi tetap dapat menjalankan debug web, DDS/VM service, dan DevTools secara nyata. Target `web-server` dapat menyajikan asset dan VM service, namun tanpa Chrome Debug Extension screenshot browser bisa tertahan di loading screen.

**How to apply:**
- Jalankan `Flutter Debug Web` dan `Flutter DevTools` secara manual untuk inspeksi runtime.
- Gunakan URL VM service/DDS yang dicetak workflow Flutter, bukan endpoint VM mentah; endpoint mentah dapat mengembalikan 403 setelah DDS mengambil alih.
- Preview release di port 5000 tetap menjadi pemeriksaan visual aplikasi yang normal.