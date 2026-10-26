Native Code Audit: ARM64 NEON Intrinsics Optimization

Perform a comprehensive audit of the entire repository's native codebase and identify which functions, algorithms, and processing stages are suitable candidates for optimization using ARM64 NEON intrinsics ("<arm_neon.h>").

1. Audit the Entire Native Codebase

Inspect all relevant native source files, headers, build configurations, and integration layers, including but not limited to:

- C and C++ implementations.
- ARM64 assembly and existing NEON implementations.
- DSP algorithms, audio processing, numerical computations, and signal analysis.
- JNI bridges and native processing pipelines.
- FFI interfaces and Flutter native-assets integration.
- Native libraries, architecture-specific implementations, and build scripts.
- Existing scalar, SIMD, and architecture-dependent code paths.

Trace how the relevant functions are called in production. Do not assess files or functions in isolation when their callers, data layouts, or downstream processing affect optimization opportunities.

2. Identify NEON Optimization Candidates

For every potentially suitable function, determine whether ARM64 NEON intrinsics could provide a meaningful improvement.

Prioritize workloads involving:

- Repeated arithmetic over arrays or audio sample buffers.
- Vectorizable DSP operations, including filtering, mixing, gain adjustment, normalization, and channel processing.
- Element-wise mathematical operations and reductions.
- Repeated floating-point computations, where vectorization preserves acceptable numerical behavior.
- Data-parallel image, signal, and feature-processing operations.
- Hot loops with measurable CPU costs and sufficient computational work to benefit from SIMD.

Evaluate existing implementations first. Do not recommend replacing code that already uses efficient NEON instructions or compiler-generated SIMD without evidence of an additional benefit.

3. Analyze Each Candidate

For every candidate, document:

1. Location: File, function, and relevant line numbers.
2. Current implementation: Algorithm, data types, memory access pattern, and existing optimization.
3. Bottleneck: Evidence that the code is computationally expensive or performance-sensitive. Distinguish confirmed bottlenecks from hypotheses.
4. NEON strategy: Which ARM64 intrinsics or vector operations are appropriate and why.
5. Expected benefit: Estimated potential improvement, clearly labeled as an estimate unless supported by measurements.
6. Correctness risks: Floating-point precision, overflow, NaN/Inf behavior, rounding, denormal values, alignment, buffer boundaries, and reduction-order differences.
7. Implementation complexity: Required changes, fallback requirements, and integration risks.
8. Validation plan: Specific tests and benchmarks needed to demonstrate correctness and performance.
9. Priority: High, Medium, or Low, based on expected practical benefit relative to implementation cost and risk.

Use exact intrinsics only when their suitability is understood. Do not invent performance figures or claim speedups without benchmark evidence.

4. Verify ARM64 Compatibility

Inspect the project's actual target architectures, minimum Android API level, compiler toolchain, and CMake or other native build configuration.

- Confirm that ARM64 NEON code is compiled and executed only on compatible targets.
- Use appropriate compile-time architecture checks and runtime dispatch only when genuinely necessary.
- Preserve a correct scalar fallback wherever other architectures or unsupported build configurations require it.
- Avoid introducing unnecessary runtime dispatch for mandatory ARM64 Advanced SIMD capabilities.
- Check ABI compatibility, compiler flags, linking, symbol visibility, and integration with existing JNI and FFI boundaries.
- Ensure any assembly and intrinsic implementations remain behaviorally consistent.

Do not assume every Android device supports identical performance characteristics simply because it supports ARM64.

5. Evaluate Performance Beyond SIMD

Before recommending NEON, determine whether the actual bottleneck is CPU arithmetic, memory bandwidth, cache misses, JNI/FFI overhead, allocations, synchronization, or inefficient algorithmic complexity.

Do not vectorize a function merely because it contains arithmetic. Consider compiler auto-vectorization, algorithm improvements, memory-layout changes, and removal of redundant work as alternatives.

NEON should be recommended only when it is likely to provide a meaningful end-to-end benefit.

6. Testing and Benchmark Requirements

Inspect existing tests and benchmark infrastructure. Identify missing coverage for:

- Scalar-versus-NEON output equivalence.
- Boundary sizes, non-vector-aligned buffer lengths, and tail handling.
- Zero-length and very small inputs where applicable.
- Unaligned input buffers when supported by the interface.
- Extreme input values, NaN, infinity, and floating-point edge cases where relevant.
- Stereo and multichannel processing.
- ARM64-specific regressions and consistency between C/C++, intrinsics, and assembly implementations.
- Realistic production workloads.

Propose repeatable benchmarks using representative workloads and report latency, throughput, CPU usage where measurable, and end-to-end impact. Include warm-up, multiple iterations, and appropriate controls against misleading results.

Do not accept microbenchmark improvements as proof of application-level gains when integration overhead could erase those gains.

7. Scope and Execution Rules

Do not blindly rewrite entire files, refactor unrelated code, introduce new dependencies, or remove existing implementations.

Base every recommendation on the actual repository contents. Clearly distinguish verified findings, static-analysis observations, and hypotheses that require runtime profiling.

If build tooling, hardware access, profiling tools, or tests are unavailable, state the limitation explicitly instead of claiming verification.

8. Required Deliverable

Produce a prioritized report containing:

1. Executive summary of the native codebase and its existing optimization level.
2. Complete inventory of inspected native components.
3. Ranked table of NEON64 optimization candidates.
4. Detailed technical analysis of each high-priority candidate.
5. Functions that should remain scalar or should not be optimized, with reasons.
6. Existing SIMD implementations that should be preserved or improved rather than replaced.
7. Recommended implementation order, including dependencies and regression risks.
8. Testing and benchmarking plan for each proposed optimization.
9. Unresolved questions and additional profiling required before implementation.

Conclude with three categories:

- Recommended: Strong candidates with a clear technical justification.
- Investigate Further: Potential candidates requiring profiling, measurement, or additional evidence.
- Do Not Convert: Functions where NEON is unlikely to help or would introduce disproportionate complexity or correctness risks.

The goal is not to maximize the number of NEON intrinsics. The goal is to identify the smallest set of high-value, evidence-based ARM64 SIMD optimizations that improve real application performance without compromising correctness, stability, maintainability, or compatibility.

Stop after delivering the report. Wait for explicit approval before implementing any changes.
