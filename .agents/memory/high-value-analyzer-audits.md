---
name: High-value analyzer audits
description: Scope and validation rules for analyzer cleanup in this Flutter project.
---

High-value analyzer cleanup harus memprioritaskan error compile-time, type safety,
async lifetime, resource safety, dan warning yang bisa memengaruhi runtime.
Lint style-only tidak perlu dikejar dalam audit yang scoped seperti ini.

**Why:** Repo memakai banyak lint strict sehingga audit penuh menghasilkan ribuan
diagnostic kosmetik; mencampurnya dengan error nyata mendorong refactor luas yang
tidak memberi manfaat runtime.

**How to apply:** Jalankan analyzer dengan target eksplisit `lib test`, laporkan
error/warning terpisah dari info style, dan tulis hasil audit permanen di file
Markdown root sesuai konvensi audit.