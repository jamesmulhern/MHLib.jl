# The function for which to tune the parameters, i.e., minimize

"""
    f(x::Float64, y::Int, z::String)::Float64

Demo function to tune with SMAC3 in different ways.
"""
function f(x::Float64, y::Int, z::String)::Float64
    # just some busy waiting for testing parallelization:
    xx=3
    for i in 1:10000000
        xx = xx + 1e-6 *sin(xx)
    end

    if z != "opt2"
        return (x + 2y + log(xx) - 2.5)^2
    else
        return 123.456
    end
end
