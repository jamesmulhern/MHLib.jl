"""Demo application solving the multi-dimensional knapsack problem (MKP).

Given are a set of n items, m resources, and a capacity for each resource.
Each item has a price and requires from each resource a certain amount.
Find a subset of the items with maximum total price that does not exceed the resources' capacities.
"""

module MKP

import Base: copy, copy!, fill!
using ArgParse

using MHLib
using MHLib.Schedulers
import MHLib.Schedulers: construct!, local_improve!, shaking!
import MHLib: calc_objective, element_removed_delta_eval!, element_added_delta_eval!, may_be_extendible

export MKPInstance, MKPSolution

struct MKPInstance
    n::Int
    m::Int
    p::Vector{Int}
    r::Array{Int,2}
    b::Vector{Int}
    r_min::Int
    obj_opt::Float64
end

function MKPInstance(file_name::String)
    local n::Int
    local m::Int
    local p::Vector{Int}
    local r::Array{Int,2}
    local b::Vector{Int}
    local r_min::Int
    local obj_opt::Float64
    all_values = Vector{Int}()

    open(file_name) do f
        for line in eachline(f)
            for word in split(line)
                push!(all_values, parse(Int,word))
            end
        end
        n = all_values[1]
        m = all_values[2]
        if length(all_values) != 3+n+m*n+m
            error("Invalid number of values in MKP instance file $(file_name)")
        end
        obj_opt = all_values[3]
        p = Vector{Int}(all_values[4:4+n-1])
        r = reshape(Vector{Int}(all_values[4+n:4+n+m*n-1]),(m,n))
        b = Vector{Int}(all_values[4+n+m*n:4+n+m*n+m-1])
        r_min = min(minimum(r),1)
    end
    MKPInstance(n, m, p, r, b, r_min, obj_opt)
end


mutable struct MKPSolution <: SubsetVectorSolution{Int}
    inst::MKPInstance
    obj_val::Int
    obj_val_valid::Bool
    x::Vector{Int}
    y::Vector{Int}
    all_elements::Set{Int}
    sel::Int
end

MKPSolution(inst::MKPInstance) =
    MKPSolution(inst, -1, false, collect(1:inst.n), zeros(inst.m), Set{Int}(1:inst.n), 0)

function copy!(s1::S, s2::S) where {S <: MKPSolution}
    s1.inst = s2.inst
    s1.obj_val = s2.obj_val
    s1.obj_val_valid = s2.obj_val_valid
    s1.x[:] = s2.x
    s1.y[:] = s2.y
    s1.all_elements = Set(s2.all_elements)
    s1.sel = s2.sel
end

copy(s::MKPSolution) =
    MKPSolution(s.inst, -1, false, Base.copy(s.x[:]), Base.copy(s.y[:]), Base.copy(s.all_elements), s.sel)

Base.show(io::IO, s::MKPSolution) =
    println(io, "Solution: ", s.x)

function calc_objective(s::MKPSolution)
    if s.sel > 0
        return sum(s.inst.p[s.x[1:s.sel]])
    end
    return 0
end

function calc_y(s::MKPSolution)
    if s.sel > 0
        s.y = sum(s.inst.r[:, s.x[:s.sel]], dims=2)
    end
    return 0
end

function check(s::MKPSolution, unsorted=false)
    invoke(calc_objective, Tuple{SubsetVectorSolution,Bool}, s, unsorted)
    y_old = s.y
    calc_y(s)
    if any(y_old .!= s.y)
        error("Solution had invalid y values: $(s.y) $(s.y_old)")
    end
    if any(s.y .> s.inst.b)
        error("Solution exceeds capacity limits: $(self.y) $(s.inst.b)")
    end
end

function clear(s::MKPSolution)
    fill!(s.y, 0)
    fill!(s)
end

function construct!(s::MKPSolution, par::Int, result::Result)
    initialize!(s)
end

function local_improve!(s::MKPSolution, par::Int, result::Result)
    if !two_exchange_random_fill_neighborhood_search!(s, false)
        result.changed = false
    end
end

function shaking!(s::MKPSolution, par::Int, result::Result)
    remove_some!(s, par)
    fill!(s, nothing)
end

function may_be_extendible(s::MKPSolution)
    return all((s.y .+ s.inst.r_min) .<= s.inst.b) && s.sel < length(s.x)
end

function element_removed_delta_eval!(s::MKPSolution; update_obj_val::Bool=true, allow_infeasible::Bool=false)
    elem = s.x[s.sel+1]
    s.y .-= s.inst.r[:, elem]
    if update_obj_val
        s.obj_val -= s.inst.p[elem]
    end
    return true
end

function element_added_delta_eval!(s::MKPSolution; update_obj_val::Bool=true, allow_infeasible::Bool=false)
    elem = s.x[s.sel]
    y_new = s.y .+ s.inst.r[:, elem]
    feasible = all(y_new .<= s.inst.b)
    if allow_infeasible || feasible
        # accept
        s.y = y_new
        if update_obj_val
            s.obj_val += s.inst.p[elem]
        end
        return feasible
    end
    # revert
    s.sel -= 1
    return false
end

end # module
