# Phase 8C — Lyrics Architecture Refactor

## Objective

Refactor the Lyrics system into a clean, single-source-of-truth architecture without changing observable behavior.

This phase focuses on:

- cache consistency
- provider architecture
- retry behavior
- rate limiting
- maintainability
- validation safety

Do NOT redesign playback.
Do NOT touch Media3.
Do NOT touch DSP.
Do NOT touch ReplayGain.
Do NOT change UI behavior unless required to preserve lyrics functionality.

---

# Source of Truth

Use ONLY the current repository state and the validated findings from:

- Revalidation_Report_2026_07_18.md

Focus on the validated Lyrics-related issues only.

Ignore:

- Rejected
- No Longer Applicable
- Do Not Fix
- unrelated findings

---

# Current Problems to Solve

Validated Lyrics issues include:

- dual cache design
- fragile provider detection
- inconsistent provider behavior
- no shared provider abstraction
- cache cleanup problems
- rate limiter timing inefficiencies
- repeated parsing / repeated allocations
- inconsistent 429 handling across providers
- code duplication across providers

---

# Main Goal

Move the Lyrics subsystem toward a single, predictable architecture.

The final design should make it obvious:

- where lyrics come from
- how provider selection works
- how cache lookup works
- how retries work
- how rate limiting works
- what the fallback order is

---

# Core Architectural Rules

## 1. Single Source of Truth

There must be one authoritative path for:

- current lyrics result
- cache lookup
- selected provider
- retry state
- failure state

If multiple caches or parallel truth sources exist, resolve that design explicitly.

Do not leave duplicated state that can drift apart.

---

## 2. Shared Provider Abstraction

Introduce a shared abstraction only if it reduces duplication and clarifies behavior.

Possible responsibilities:

- request building
- response parsing
- error normalization
- retry classification
- 429 handling
- source metadata

Do NOT over-abstract.

If a base class is used, it must be genuinely useful.

---

## 3. Provider Behavior

Provider behavior must remain functionally identical.

Do not change:

- result ranking
- source ordering
- search fallback logic
- sync/unsync detection rules
- translation handling
- provider selection semantics

If any behavior must change for architecture reasons, document it first and keep it minimal.

---

## 4. Cache Design

Resolve the cache architecture problem.

Possible safe directions:

- one authoritative cache manager
- clear ownership boundaries
- bounded in-memory cache
- explicit TTL or invalidation rules
- deterministic cleanup

Do not let static maps and manager classes both act as separate sources of truth.

---

## 5. Rate Limiting

Improve rate limiting design so it is:

- predictable
- easy to reason about
- cheap to evaluate
- testable

Do not introduce timer-heavy solutions.

Do not make rate limiting dependent on unstable wall-clock behavior if a monotonic clock is safer.

---

## 6. Retry / 429 Handling

Normalize provider error handling.

A provider should be able to express:

- success
- no result
- retryable failure
- rate-limited failure
- permanent failure

Use a consistent model across providers.

---

## 7. Parsing / Allocation

Reduce repeated parsing where it is validated and safe.

Examples:

- avoid repeated JSON decoding when the same data is reused
- avoid repeated Map/List allocations where unnecessary
- avoid repeated string scanning when a token/enum would be safer

Do not micro-optimize blindly.

---

# Implementation Constraints

Do NOT:

- change playback pipeline
- change Media3
- change DSP
- change ReplayGain
- change artwork pipeline
- change unrelated UI
- add new features
- alter lyrics output semantics unless necessary to fix the architecture

Keep behavior stable.

---

# Safety Rules

Before moving or deleting any code, verify:

- no hidden caller depends on it
- no provider behavior changes unexpectedly
- no fallback path is lost
- no cache invalidation path is broken
- no regression in synced lyrics
- no regression in unsynced lyrics
- no regression in translation display
- no regression in provider switching

If a change risks altering behavior, stop and document it.

---

# Suggested Refactor Targets

## A. Lyrics Cache

Audit all lyrics cache logic and consolidate it.

Possible outputs:

- a single cache manager
- one memory cache policy
- one disk cache policy
- one invalidation policy
- one lookup order

---

## B. Provider Base / Interface

If useful, create a shared contract for providers.

This contract should define:

- source id
- source name
- fetch API
- parse API
- error classification
- rate-limit classification

---

## C. Fetch Orchestrator

Create or clean up a single orchestrator for fetch flow.

It should own:

- source ordering
- retries
- fallback
- provider result normalization
- cache read/write interaction

---

## D. Rate Limiter

Make rate limiting easy to test.

Prefer deterministic logic over ad-hoc timing checks.

---

## E. Error Model

Normalize provider errors into a small set of categories.

Avoid scattered string matching where possible.

---

# Validation

After refactor, verify:

- flutter analyze
- lyrics fetch still works
- synced lyrics still work
- unsynced lyrics still work
- translation still works
- provider switching still works
- cache still works
- rate limiting still works
- no behavior regression on Mi 9T

If available, run focused tests or a reproducible manual verification flow.

---

# Deliverables

## 1. Architecture Report

Explain:

- what the old architecture was
- what the new architecture is
- why the change is better
- what became the single source of truth

---

## 2. Changed Files

List every modified file.

---

## 3. Behavioral Equivalence Report

Confirm what stayed identical:

- lyrics output
- fallback order
- provider switching
- sync behavior
- UI behavior

---

## 4. Risk Report

List any behavior that could still differ and why.

---

## 5. Validation Report

Include:

- flutter analyze result
- build status
- manual verification notes

---

# Stop Condition

Stop after completing the Lyrics Architecture refactor.

Do not continue into Player Background refactor.
Do not start any unrelated cleanup.
