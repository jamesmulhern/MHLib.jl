using Test
using MHLib
using MHLib.Scheduler
using MHLib.OneMax
using Random

@testset "MHLib.jl" begin
    parse_settings!(["--seed=1"])
    println(get_settings_as_string())
    s1 = OneMaxSolution{5}()
    initialize!(s1)
    s2 = OneMaxSolution{5}()
    initialize!(s2)
    s3 = copy(s1)
    initialize!(s3)
    copy!(s1,s3)
    # println("$s1, $(obj(s1))\n$s2, $(obj(s2))\n$s3, $(obj(s3))")
    @test is_equal(s1, s3)
    @test dist(s1, s3) == 0
    s1.x[1] = !s1.x[1]; invalidate!(s1)
    @test !is_equal(s1, s3)
    @test dist(s1, s3) == 1
    # println("$s1, $(obj(s1))")
    check(s1)
end

@testset "scheduler.jl" begin
    parse_settings!(["--seed=1"])
    sol = OneMaxSolution{10}()
    println(sol)
    methods = [MHMethod("con", construct!, 0),
        MHMethod("li1", local_improve!, 1),
        MHMethod("sh1", shaking!, 1),
        MHMethod("sh2", shaking!, 2),
        MHMethod("sh3", shaking!, 3)]
    sched = MHScheduler(sol, methods)
    for m in next_method(methods)
        perform_method!(sched, m, sol)
        println(sol)
    end
    main_results(sched)
    check(sol)
    @test obj(sol) >= 0
end
