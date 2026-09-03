# LocalMath.jl

LocalMath is a typed, bounded, conflict-aware language for local scientific
computation on CPU and GPU through one KernelAbstractions execution path.

Start with [Quick start](learn/localmath-quickstart.md), then use
[Relations and storage](learn/localmath-relations.md) and the
[Scientific recipes](learn/localmath-recipes.md) for complete models.

## One architecture, from equation to device

LocalMath keeps mathematical meaning and physical execution separate without
creating parallel representations:

```text
@localmath
    → LocalLaw
    → bind (validated descriptors and scientific storage)
    → Plan (backend-independent meaning plus a concrete lowering)
    → PreparedPlan (workspace, provider, and device realization)
    → KernelAbstractions launches
    → ExecutionReceipt
```

`inspect` and `compilation_report` project facts from those existing values;
execution never consumes a report. CPU and qualified GPU backends use the same
laws, validation, packed storage, and KernelAbstractions execution path.
