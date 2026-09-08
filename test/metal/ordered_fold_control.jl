using Metal
include(joinpath(@__DIR__, "..", "fixtures", "ordered_fold_control_contracts.jl"))
Metal.functional() || error("ordered-fold control tests require functional Metal")
Metal.allowscalar(false)
ordered_fold_control_contracts(Metal.MtlArray)
