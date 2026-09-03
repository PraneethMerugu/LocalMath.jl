"""Cold inspection of planned and prepared LocalMath programs.

This file projects facts from the semantic law, validated binding, physical
lowering, and prepared runtime. Execution never consumes these projections.
"""

"""
    LocalMath.inspect(plan::Plan)

Return the semantic projection together with validated relation proofs,
producer dependencies, workspace requirements, specialization signatures, and
the currently planned physical phases. Physical planning fields describe the
current implementation and are not additional scientific semantics.
"""
inspect(plan::Plan{<:_BoundLaw}; level = nothing) =
    _inspection_projection(_plan_inspection(plan, :Plan), level)

_structural_leaf_inspection(fact::_StructuralLeafFact) = (
    name = fact.name,
    storage_type = fact.storage_type,
    logical = fact.logical,
    prepared = fact.prepared,
)

function _binding_realization(binding::_ValidatedStructuralBinding)
    fields = map(binding.fields, binding.field_facts) do value, facts
        (identity = semantic_identity(value.field),
            binding_identity = value.binding_id,
            ownership = _ownership_inspection(value.ownership),
            leaves = map(_structural_leaf_inspection, facts))
    end
    relations = map(binding.relations, binding.proofs) do value, proof
        (identity = semantic_identity(value.relation),
            binding_identity = value.binding_id,
            ownership = _ownership_inspection(value.ownership),
            dynamic_generation = value.generation !== nothing,
            dynamic_status = value.status !== nothing,
            leaves = map(_structural_leaf_inspection,
                proof.binding_schema.physical_leaves))
    end
    collections = map(binding.collections,
            binding.collection_facts) do value, facts
        (identity = semantic_identity(value.collection),
            binding_identity = value.binding_id,
            leaves = map(_structural_leaf_inspection, facts))
    end
    return (; fields, relations, collections)
end

"""
    LocalMath.inspect(prepared::PreparedPlan)

Return the plan projection plus concrete storage, callable admission, provider,
workspace, submission-layout, and mutable receipt-counter observations. The
operation is cold and does not submit or synchronize work.
"""
function inspect(prepared::PreparedPlan; level = nothing)
    report = _plan_inspection(prepared.plan, :PreparedPlan; prepared)
    callbacks = map(prepared.plan.lowering.callable_admissions) do entry
        (purpose = entry.purpose, signature = entry.signature,
            return_type = entry.return_type,
            admission = entry.admission,
            method = entry.method)
    end
    realized = (
        prepared_launch_types = Tuple(map(launch -> typeof(launch.stage),
            prepared.runtime.launches)),
        callback_methods = callbacks,
        provider = _lane_provider(prepared.lane),
        device = _lane_device(prepared.lane),
        bindings = _binding_realization(prepared.plan.bound.binding),
        parameter_layout = _stage_parameter_layout_inspection(
            prepared.submission_schema),
        dependency_arity = prepared.dependency_arity,
        lease_capacity = length(prepared.leases),
        workspace_ownership = prepared.workspace_ownership,
        state = (
            submitted = prepared.submitted,
            drained = prepared.drained,
            outstanding = prepared.outstanding,
            poisoned = prepared.poisoned,
            provider_completions = _lane_wait_count(prepared.lane),
            provider_scope_completions =
                _lane_scope_wait_count(prepared.lane),
            validation_transfers = _lane_transfer_count(prepared.lane),
        ),
    )
    return _inspection_projection(merge(report, (; realized)), level)
end

function _distinct_specialization_count(stages)
    signatures = map(stage -> stage.planning.specialization_signature, stages)
    return length(unique(signatures))
end

_callable_admission_inspection(entry::_CallableAdmissionFact) = (
    purpose = entry.purpose,
    callable_type = typeof(entry.callback),
    selected_method = entry.method,
    analyzed_signature = entry.signature,
    inferred_return_type = entry.return_type,
    admission_contract = entry.admission,
)

"""
    LocalMath.compilation_report(plan::Plan)

Return cold structural compiler facts: specialization families, callable
signatures, physical phases, relationship validation, and workspace shape.
The report contains no predicted wall time and is never consumed by planning.
"""
function compilation_report(plan::Plan{<:_BoundLaw})
    report = _plan_inspection(plan, :Plan)
    return (
        lifecycle = :PlanCompilationReport,
        compiler = report.planning.compiler,
        stage_count = length(report.stages),
        specialization_family_count = _distinct_specialization_count(
            report.stages),
        specialization_signatures = map(
            stage -> stage.planning.specialization_signature, report.stages),
        callable_signatures = map(
            stage -> stage.planning.evaluator_signature, report.stages),
        callable_admissions = map(_callable_admission_inspection,
            plan.lowering.callable_admissions),
        relationship_receipts = map(
            stage -> stage.planning.relationship_receipts, report.stages),
        stage_phases = report.planning.stage_phases,
        provider_launch_count = report.planning.base_provider_launch_count,
        workspace = report.planning.workspace,
        workspace_bytes = report.planning.workspace_bytes,
    )
end

"""
    LocalMath.compilation_report(prepared::PreparedPlan)

Return the plan report together with realized launch types, selected callback
methods, parameter layout, dependency arity, and provider facts. This operation
does not submit work or synchronize the provider.
"""
function compilation_report(prepared::PreparedPlan)
    planned = compilation_report(prepared.plan)
    report = inspect(prepared)
    return merge(planned, (
        lifecycle = :PreparedCompilationReport,
        prepared_launch_types = report.realized.prepared_launch_types,
        callback_methods = report.realized.callback_methods,
        parameter_layout = report.realized.parameter_layout,
        dependency_arity = report.realized.dependency_arity,
        provider = report.realized.provider,
        device = report.realized.device,
    ))
end

"""`execution_contract(prepared)` reports provider-scope receipt behavior without submitting work."""
function execution_contract(prepared::PreparedPlan)
    lane = prepared.lane
    return (
        provider = _lane_provider(lane),
        receipt_scope = _lane_wait_scope(lane),
        receipt_cumulative = _lane_cumulative(lane),
        receipt_selective = _lane_selective(lane),
        observed_provider_completions = _lane_wait_count(lane),
        observed_scope_completions = _lane_scope_wait_count(lane),
        observed_validation_transfers = _lane_transfer_count(lane),
    )
end
