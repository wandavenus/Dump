---
name: Analyzer output filtering
description: Workflow convention for showing only actionable analyzer diagnostics.
---

Workflow analyzer memakai wrapper output, bukan mematikan lint di
`analysis_options.yaml`: info-level lint disembunyikan dari tampilan dan tidak
dianggap fatal, sedangkan error dan warning tetap ditampilkan serta menentukan
exit status workflow.

**Why:** Project memiliki ribuan info style-only yang menutupi diagnostic
actionable dan membuat workflow tampak gagal walaupun kode berhasil dianalisis.

**How to apply:** Pertahankan `--no-fatal-infos` di wrapper, jangan menghapus
aturan lint global hanya demi merapikan output, dan pastikan warning tetap fatal.