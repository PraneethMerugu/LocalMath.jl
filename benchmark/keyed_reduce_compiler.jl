#!/usr/bin/env julia

# Reproducible compiler/allocation evidence for the warm sparse-key boundary.
import KernelAbstractions
import LocalMath
import TOML

struct KeyedCompilerNode end
struct KeyedCompilerEvaluator end
@inline (::KeyedCompilerEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution(
        (UInt32(isodd(item)), UInt32(item)), Int32(1)))

struct CollectCompilerEvaluator end
@inline (::CollectCompilerEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.CollectedValue(item))

struct KeyedCompilerSubtract end
@inline (::KeyedCompilerSubtract)(left::Int32, right::Int32) = left - right

function keyed_compiler_preparation(capacity::Int;
        operation = +, retention = LocalMath.DropIdentityKeys())
    source = LocalMath.Space(KeyedCompilerNode, 3)
    key_type = Tuple{UInt32,UInt32}
    collection = LocalMath.Collection(
        LocalMath.KeyedValue{key_type,Int32}, capacity)
    stage = LocalMath.Stage(source, NamedTuple(), (
        LocalMath.Publication(collection,
            LocalMath.KeyedReduce(key_type, Int32, operation;
                seed = LocalMath.NewKeyIdentity(Int32(0)), retention);
            value = :delta),),
        LocalMath.Evaluator(KeyedCompilerEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:keyed_reduce_compiler, 1))
    return LocalMath.prepare(LocalMath.LocalLaw(stage),
        collection => LocalMath.Allocate();
        backend = KernelAbstractions.CPU())
end

function collect_compiler_preparation(capacity::Int)
    source = LocalMath.Space(KeyedCompilerNode, 3)
    collection = LocalMath.Collection(Int32, capacity)
    stage = LocalMath.Stage(source, NamedTuple(), (
        LocalMath.Publication(collection,
            LocalMath.Collect(Int32; maximum = 1); value = :delta),),
        LocalMath.Evaluator(CollectCompilerEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:collect_compiler_control, 1))
    return LocalMath.prepare(LocalMath.LocalLaw(stage),
        collection => LocalMath.Allocate();
        backend = KernelAbstractions.CPU())
end

function typed_metrics(callable, signature)
    info, return_type = only(Base.code_typed_by_type(
        Tuple{typeof(callable),signature.parameters...}; optimize = true))
    calls = count(statement -> statement isa Expr &&
        statement.head in (:call, :invoke), info.code)
    any_indices = filter(index -> info.ssavaluetypes[index] === Any,
        eachindex(info.code))
    control_flow = statement -> statement isa Union{
        Core.GotoNode,Core.GotoIfNot,Core.ReturnNode}
    return Dict(
        "statement_count" => length(info.code),
        "call_count" => calls,
        "any_ssa_count" => length(any_indices),
        "any_control_flow_count" => count(
            index -> control_flow(info.code[index]), any_indices),
        "any_value_count" => count(
            index -> !control_flow(info.code[index]), any_indices),
        "return_type" => string(return_type),
    )
end

function warm_public_execution_allocations(prepared)
    wait(LocalMath.execute!(prepared))
    return minimum(@allocated(wait(LocalMath.execute!(prepared))) for _ in 1:5)
end

function keyed_compiler_metrics(prepared)
    launch = only(getfield(getfield(prepared, :runtime), :launches))
    stage = getfield(launch, :stage)
    validation = LocalMath._ProgramValidationTarget(
        getfield(getfield(prepared, :runtime), :execution_gate), Int32(1))
    signature = Tuple{typeof(stage),Tuple{},Int32,Tuple{},
        typeof(getfield(launch, :guard)),typeof(validation)}
    host = typed_metrics(LocalMath._execute_keyed_reduce_stage!, signature)
    execution = getfield(stage, :execution)
    plan = getfield(execution, :plan)
    states = getfield(execution, :states)
    emission = LocalMath.KeyedContribution(
        (UInt32(1), UInt32(1)), Int32(1))
    semantic_signature = Tuple{typeof(plan.emission),typeof(states.emission),
        typeof(emission),Int32}
    semantic = typed_metrics(LocalMath._keyed_reduce_materialize!,
        semantic_signature)
    allocated = warm_public_execution_allocations(prepared)
    return Dict(
        "host_orchestration" => host,
        "emission_boundary" => semantic,
        "sort_boundary" => typed_metrics(LocalMath._compacted_ordinal_less,
            Tuple{typeof(plan.key_order),typeof(states.ordering),Int32,Int32}),
        "fold_boundary" => typed_metrics(LocalMath._keyed_reduce_fold_segment!,
            Tuple{typeof(plan.fold),typeof(states.fold),
                typeof(states.ordering.order_a),Int32,Int32}),
        "publish_boundary" => typed_metrics(LocalMath._keyed_reduce_publish_record!,
            Tuple{typeof(plan.publication),typeof(states.publication),
                typeof(execution.storage),Int32,Int32}),
        "warm_public_execution_allocated_bytes" => allocated,
        "host_any_classes" => [
            "KernelAbstractions launch construction (_svec_ref and kwcall)",
            "compacted scan/order launch calls whose host return is unused",
            "host control-flow and return nodes represented as Any by CodeInfo",
        ],
        "allocation_root_classes" => [
            "shared ExecutionReceipt and validation-status grouping",
            "KernelAbstractions Kernel, NDRange, keyword, and argument tuples per launch",
        ],
        "prepared_stage_type" => string(typeof(stage)),
    )
end

function collect_compiler_metrics(prepared)
    launch = only(getfield(getfield(prepared, :runtime), :launches))
    stage = getfield(launch, :stage)
    validation = LocalMath._ProgramValidationTarget(
        getfield(getfield(prepared, :runtime), :execution_gate), Int32(1))
    signature = Tuple{typeof(stage),Tuple{},Int32,Tuple{},
        typeof(getfield(launch, :guard)),typeof(validation)}
    return typed_metrics(LocalMath._execute_collect_stage!, signature)
end

preparations = map(capacity -> keyed_compiler_preparation(capacity), (4, 8))
variants = (
    keyed_compiler_preparation(4; operation = +,
        retention = LocalMath.DropIdentityKeys()),
    keyed_compiler_preparation(4; operation = +,
        retention = LocalMath.RetainAllKeys()),
    keyed_compiler_preparation(4; operation = KeyedCompilerSubtract(),
        retention = LocalMath.DropIdentityKeys()),
    keyed_compiler_preparation(4; operation = KeyedCompilerSubtract(),
        retention = LocalMath.RetainAllKeys()),
)
metrics = keyed_compiler_metrics(first(preparations))
control = collect_compiler_preparation(4)
metrics["collect_host_orchestration"] = collect_compiler_metrics(control)
control_allocated = warm_public_execution_allocations(control)
metrics["collect_control_allocated_bytes"] = control_allocated
metrics["keyed_incremental_allocated_bytes"] =
    metrics["warm_public_execution_allocated_bytes"] - control_allocated
metrics["capacity_specialization_count"] = length(unique(typeof(
    getfield(only(getfield(getfield(prepared, :runtime), :launches)), :stage))
    for prepared in preparations))
variant_parts = map(variants) do prepared
    execution = getfield(getfield(only(getfield(
        getfield(prepared, :runtime), :launches)), :stage), :execution)
    (; plan = execution.plan, states = execution.states,
        storage = execution.storage)
end
metrics["operation_retention_specializations"] = Dict(
    "bounds" => length(unique(typeof(part.plan.bounds) for part in variant_parts)),
    "emission" => length(unique(typeof(part.plan.emission) for part in variant_parts)),
    "sort" => length(unique((typeof(part.plan.key_order),
        typeof(part.states.ordering)) for part in variant_parts)),
    "segment" => length(unique((typeof(part.plan.key_order),
        typeof(part.states.segment)) for part in variant_parts)),
    "fold" => length(unique((typeof(part.plan.fold),
        typeof(part.states.fold)) for part in variant_parts)),
    "finalize" => length(unique((typeof(part.plan.bounds),
        typeof(part.states.final)) for part in variant_parts)),
    "publish" => length(unique((typeof(part.plan.publication),
        typeof(part.states.publication), typeof(part.storage))
        for part in variant_parts)),
)
metrics["kaimon"] = "executed through a Kaimon persistent LocalMath project session; metrics are produced by these reproducible Base.code_typed_by_type probes"
TOML.print(stdout, Dict("keyed_reduce" => metrics); sorted = true)
println()
