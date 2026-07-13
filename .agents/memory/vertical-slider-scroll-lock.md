---
name: Vertical slider vs vertical ScrollView gesture conflict
description: A raw-Listener-based vertical drag slider nested inside a vertical SingleChildScrollView/ListView will make the page scroll while dragging, because Listener never joins the gesture arena and can't out-compete the ancestor Scrollable's own vertical drag recognizer.
---

Any custom draggable control implemented with a raw `Listener` (chosen for
multitouch-safety, since `GestureDetector`/drag recognizers only track one
pointer per widget by default) does not participate in the Flutter gesture
arena. If it sits inside an ancestor `Scrollable` that scrolls on the same
axis (vertical slider inside a vertical `SingleChildScrollView`), the
Scrollable's own recognizer sees the same pointer events and starts
scrolling — the page jumps around while the user tries to drag the slider.

**Why:** `Listener` intentionally bypasses arena participation so multiple
simultaneous pointers (e.g. dragging several sliders with different fingers)
each get independent, un-arbitrated raw event streams. But that also means
nothing stops the ancestor Scrollable's recognizer from claiming the same
pointer.

**How to apply:** Don't fight the arena — sidestep it. Have the
Listener-based controls report an active-pointer count up to a shared
`ValueNotifier<int>` (incremented on pointer down, decremented on pointer
up/cancel, with a dispose()-time safety decrement in case the widget is
torn down mid-drag). Wrap the ancestor `SingleChildScrollView`/`ListView` in
a `ValueListenableBuilder` on that counter and swap its `physics` to
`NeverScrollableScrollPhysics()` while count > 0, restoring normal physics
at 0. This fully locks page scroll during any slider interaction without
touching the sliders' own multitouch-safe Listener implementation.
