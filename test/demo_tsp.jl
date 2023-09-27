#!/usr/bin/env julia
"""
    demo_tsp.jl

Standalone demo program for solving the TSP.
For other demos see `runtests.jl`.
"""

# always run this code in the test directory and the test environment
cd(@__DIR__)
using Pkg; Pkg.activate(".")
using ArgParse
using Random
using Revise

if isdefined(@__MODULE__, :LanguageServer)  # hack for VSCode to see symbols
    include("../src/MHLib.jl")
    using .MHLib
    using .MHLib.Schedulers
    using .MHLib.GVNSs
    using .MHLib.LNSs
else
    using MHLib
    using MHLib.Schedulers
    using MHLib.GVNSs
    using MHLib.LNSs
end

includet("TSP.jl")
using .TSP

const settings_cfg = ArgParseSettings()

@add_arg_table! settings_cfg begin
    "--alg"
        help = "Algorithm to apply (gvns, lns)"
        arg_type = String
        default = "lns"
end

function solve_tsp()
    inst = TSPInstance("data/xqf131.tsp")
    sol = TSPSolution(inst)
    initialize!(sol)
    println(sol)

    if settings[:alg] === "lns"
        alg = LNS(sol, MHMethod[MHMethod("con", construct!, 0)],
            [MHMethod("de$i", LNSs.destroy!, i) for i in 1:3],
            [MHMethod("re", LNSs.repair!, 1)], 
            consider_initial_sol = true)
    elseif settings[:alg] === "gvns"
        alg = GVNS(sol, [MHMethod("con", construct!, 0)],
        [MHMethod("li1", local_improve!, 1)],[MHMethod("sh1", shaking!, 1)], 
        consider_initial_sol = true)
    else
        error("Invalid parameter alg: $(settings[:alg])")
    end
    run!(alg)
    method_statistics(alg.scheduler)
    main_results(alg.scheduler)
    check(sol)
    return sol
end


println("TSP Demo version $(git_version())\nARGS: ", ARGS)
settings_new_default_value!(MHLib.settings_cfg, "ifile", "data/maxsat-adv1.cnf")
settings_new_default_value!(MHLib.Schedulers.settings_cfg, "mh_titer", 10000)
parse_settings!([MHLib.Schedulers.settings_cfg, MHLib.LNSs.settings_cfg, settings_cfg])
println(get_settings_as_string())

solve_tsp()
# @profview solve_tsp()