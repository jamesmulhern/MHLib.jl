"""
    LCS

Longest Common Subsequence (LCS) problem.

Find a sequence of maximum length that is a subsequence of all given input sequences.
This is a demo problem in particular for the Monte Carlo Tree Search (MCTS).
"""
module LCS

using Random
using MHLib
using ArgParse
using Flux

import Base: copy, copy!, show, append!
import MHLib: calc_objective
import MHLib.Environments:
    Environment,
    Observation,
    State,
    get_state,
    set_state!,
    action_space_size,
    observation_space_size,
    step!,
    reset!

export Alphabet, LCSInstance, LCSSolution, LCSEnvironment,
  set_prior_function!, save, call_external_solver, LCSNetwork

const settings_cfg = ArgParseSettings()

@add_arg_table! settings_cfg begin
    "--lcs_always_new_seqs"
        help = "LCS: Always create new strings when reset is called"
        arg_type = Bool
        default = false
    "--lcs_reward_mode"
        help = "LCS reward mode: direct or smallsteps"
        arg_type = String
        default = "smallsteps"
    "--lcs_prior_heuristic"
        help = "LCS-specific heuristic prior function: none or UB1 or RL (Reinforcement Learning)"
        arg_type = String
        default = "none"
    "--lcs_use_external_solver"
        help = "Boolean: Should an external solver be used to estimate an optimal solution?"
        arg_type = Bool
        default = true
end


"""
    Alphabet

Type used for letters in the LCS problem.
"""
const Alphabet = Int16

const alphabets = Dict(4 => "ACGT", 20 => "ACDEFGHIKLMNPQRSTVWY")

function get_alphabet(sigma)
    if sigma in alphabets.keys
        a = alphabets[sigma]
        Dict{Char,Alphabet}(a[i] => Alphabet(i) for i = 1:sigma)
    else
        Dict{Char,Alphabet}()  # empty for unsupported alphabets
    end
end

"""
A Longest Common Subsequence (LCS) problem instance.

The goal is to find a maximum length sequence that is a subsequence of all given input
strings.

Attributes
- `m`: number of input strings
- `n`: maximum length of input strings
- `sigma`: alphabet size, the alphabet is 1,...,sigma
- `alphabet`: dictionary translating ASCII letters to numerical values in sequences
    for supported alphabets
- `s`: vector of m input sequences of length at most n
- `succ[i, j, c]`: index of next occurrence of c in s[i] from position j onward
- `count[i, j, c]`: number of further appearances of c in s[i] from position j onward
- `external_result`: result (string length) of an external solver. -1 means "no result"
"""
struct LCSInstance
    m::Int
    n::Int
    sigma::Alphabet
    alphabet::Dict{Char,Alphabet}
    s::Vector{Vector{Alphabet}}
    succ::Array{Int,3}
    count::Array{Int,3}
    external_result::Int
end

"""
    LCSInstance(m, n, sigma)

Create a random LCSInstance with m strings of length n from alphabet 1,...,sigma.
"""
function LCSInstance(m::Int, n::Int, sigma)
    @assert n > 0 && m > 0 && sigma > 0
    inst = LCSInstance(
        m,
        n,
        Alphabet(sigma),
        get_alphabet(sigma),
        [rand(Alphabet(1):Alphabet(sigma), n) for i = 1:m],
        zeros(Int, (m, n + 1, sigma)),
        zeros(Int, (m, n + 1, sigma)),
        -1
    )
    determine_aux_data_structures(inst)
    return inst
end

"""
    LCSInstance(file)

Read LCS problem instance from file with given name.
"""
function LCSInstance(file::String)
    local s, m, sigma, alphabet
    open(file) do f
        m, sigma = [parse(Int, x) for x in split(readline(f))]
        alphabet = get_alphabet(sigma)
        s = Vector{Vector{Alphabet}}(undef, m)
        for i = 1:m
            n_str, str = split(readline(f))
            @assert length(str) == parse(Int, n_str)
            s[i] = [alphabet[c] for c in str]
        end
    end
    n = maximum(length(si) for si in s)

    res = settings[:lcs_use_external_solver] ? call_external_solver(file) : -1

    inst = LCSInstance(
        m,
        n,
        Alphabet(sigma),
        alphabet,
        s,
        zeros(Int, (m, n + 1, sigma)),
        zeros(Int, (m, n + 1, sigma)),
        res
    )
    determine_aux_data_structures(inst)
    return inst
end

"""
    call_external_solver(file)

Call bin/lcs_external_solver.sh for solving the LCS instance in the given file
and return solution length.
"""
function call_external_solver(file::AbstractString)::Int
    s = read(`bash binlcs_external_solver.sh $file`, String)
    parse(Int, split(s)[2])
end

"""
    save(inst, filename)

Saves LCS problem instance to a file with given name.
"""
function save(inst::LCSInstance, file::AbstractString)
    res = string(inst.m) * " " * string(inst.sigma) * "\n"
    for i in 1:length(inst.s)
        x = inst.s[i]
        temp = string(length(x)) * " "
        a = alphabets[inst.sigma]
        for j in 1:length(x)
            temp = temp * a[x[j]]
        end
        res = res * temp * "\n"
    end

    open(file, "w") do io
        write(io, res)
    end;
end

"""
    create_random_seqs!(inst)

Randomly re-initialize the sequences in the given LCS problem instance.
"""
function create_random_seqs!(inst::LCSInstance)
    for i = 1:inst.m
        rand!(inst.s[i], one(Alphabet):inst.sigma)
    end
    determine_aux_data_structures(inst)

    inst.external_result = -1
    if settings[:lcs_use_external_solver]
        save(inst, "./data/temp.lcs")
        inst.external_result = call_external_solver("./data/temp.lcs")
    end
end

Base.show(io::IO, inst::LCSInstance) = show(io, MIME"text/plain"(), inst.s)

"""
    determine_aux_data_structure(inst)

Determine auxiliary data structures succ and count.
"""
function determine_aux_data_structures(inst::LCSInstance)
    for i = 1:inst.m
        for c = 1:inst.sigma
            pos = 0
            count = 0
            for j = inst.n:-1:1
                if inst.s[i][j] == c
                    pos = j
                    count += 1
                end
                inst.succ[i, j, c] = pos
                inst.count[i, j, c] = count
            end
        end
    end
end

"""
    update_p(inst, p, c)

Update position vector p to refer to positions after the next occurrence of letter c in
each string.

Letter c must occur in each string s[i] from positions p[i] onward.
"""
function update_p(inst::LCSInstance, p::Vector, c)
    for i = 1:inst.m
        j = inst.succ[i, p[i], c]
        @assert j > 0
        p[i] = j + 1
    end
end


#------------------------------------------------------------------------------

"""
Solution to an LCS problem instance.

Attributes
- `inst`: LCS problem instance
- `obj_val`: Length of solution string, must always be correct
- `obj_val_valid`: Should always be true
- `s::Vector{Alphabet}`: Vector containing solution sequence of length `obj_val`,
    the vector may be longer than `obj_val`
"""
mutable struct LCSSolution <: Solution
    inst::LCSInstance
    obj_val::Int
    obj_val_valid::Bool
    s::Vector{Alphabet}
end


function Base.string(sol::LCSSolution)
    res = "LCSSolution:"
    res = res * "\n  obj_val: " * string(sol.obj_val)
    res = res * "\n  s:" * string(sol.s)
    return (res)
end


"""
    LCSSolution(inst)

Creates an empty solution for the given LCS problem instance.
"""
LCSSolution(inst::LCSInstance) =
    LCSSolution(inst, 0, true, zeros(Alphabet, inst.n))

function copy!(sol1::LCSSolution, sol2::LCSSolution)
    sol1.inst = sol2.inst
    sol1.obj_val = sol2.obj_val
    sol1.obj_val_valid = sol2.obj_val_valid
    sol1.s[:] = sol2.s
end

copy(sol::LCSSolution) = deepcopy(sol)

function Base.show(io::IO, sol::LCSSolution)
    l = sol.obj_val
    print(io, "Solution: ", l, " ")
    show(io, sol.s[1:l])
end

"""
    calc_objective(::LCSSolution)

The length of the solution is stored in sol.obj_val and must always be valid.
"""
calc_objective(sol::LCSSolution)::Int = sol.obj_val

"""
    append!(sol, c)

Append letter c to solution.
"""
append!(sol::LCSSolution, c) = sol.s[sol.obj_val+=1] = c


"""
    LCSState

State in an LCSEnvironment.

Attributes
- `p`: position vector: the sequences are still relevant from this positions onward
- `s`: current (partial) solution; TODO: now just for debugging, can be replaced later
    by just the length of the solution (if necessary at all)
"""
struct LCSState <: State
    p::Vector{Int}
    s::Vector{Int}
end


Base.string(state::LCSState) =
    "State:" * "\n  Position Vector: " * Base.string(state.p) *
    "\n  Partial Solution: " * Base.string(state.s)

function copy!(state::LCSState, state1::LCSState)
    state.p[:] = state1.p
    copy!(state.s, state1.s)
end


"""
    LCSEnvironment

Environment for solving the LCS problem.

Attributes
- `inst`: `LCSInstance` to solve
- `prior_heuristic`: heuristic to be used to determine priors
- `prior_function`: function to be used to determine priors
- `state`: current state
- `action_mask`: vector indicating currently valid actions
- `seq_order`: order of sequences in current observation
- `action_order`: order of actions in current observation
"""
mutable struct LCSEnvironment <: Environment
    inst::LCSInstance

    # GR TODO: Bitte prior_heuristic und prior_function hier entfernen, das passt hier einfach nich her.
    # prior_heuristic ist doch eher ein Parameter und generell sollte das LCSEnvironment völlig unabhängig
    # von irgendeinem Lösungsalgorithmus sein! UB1 besser als normale Funktion definieren, der MCTS
    # ggfs als Parameter mitgeben, so wie ein Alphazero-Actor seine NN-Funktion auch der MCTS übergibt.
    prior_heuristic::String
    prior_function::Function

    state::LCSState
    # TODO Daniel: action_mask ist doppelt definiert (auch in observation)
    # nur in observation belassen?
    action_mask::Vector{Bool}
    seq_order::Vector{Int}
    action_order::Vector{Int}

    function LCSEnvironment(inst::LCSInstance)
        p = ones(Int, inst.m)
        state = LCSState(p, Int[])
        action_mask = ones(Bool, inst.sigma)
        prior_heuristic = settings[:lcs_prior_heuristic]

        local fun
        if prior_heuristic === "none"
            fun = (env::LCSEnvironment, action_values::Vector{<:Real}) -> Float32[]
            # priors = Float32[]
        elseif prior_heuristic === "RL"
            # Remains undefined here, but can be set from outside
            fun = (env::LCSEnvironment, action_values::Vector{<:Real}) -> error("lcs_prior_heuristic: $(env.prior_heuristic): RL not set!")
        elseif prior_heuristic === "UB1"
            function fun_ub(env::LCSEnvironment, action_values::Vector{<:Real})
                priors = zeros(Float32, env.inst.sigma)
                p = env.state.p
                for c = 1:env.inst.sigma
                    if env.action_mask[c]
                        p_after_adding_c = [env.inst.succ[i, p[i], c] + 1 for i in 1:env.inst.m]
                        priors[c] = 1 + sum(remaining_letter_counts(env, p_after_adding_c))
                    end
                end
                # TODO: Rethink again
                priors[action_mask] = priors[action_mask] .- (minimum(priors[action_mask]) - 1)
                # priors[action_mask] = 10 .^ priors[action_mask]
                priors = priors / sum(priors)
                return priors
            end
            fun = fun_ub
        else
            error("Invalid parameter lcs_prior_heuristic: $(prior_heuristic)")
        end

        new(inst, prior_heuristic, fun, state, action_mask, Int[], Int[])
    end
end


"""
    state_space_size(env)

Return size of the state space.
"""
state_space_size(state::LCSEnvironment)::Int
    return env.inst.m + env.inst.sigma
end


function set_prior_function!(env::LCSEnvironment, fun::Function)
    env.prior_function = fun
end

action_space_size(env::LCSEnvironment) = env.inst.sigma

observation_space_size(env::LCSEnvironment) =
    env.inst.m + env.inst.sigma + env.inst.sigma * env.inst.m

get_state(env::LCSEnvironment) = env.state

function set_state!(env::LCSEnvironment, state::LCSState, obs::Observation)
    copy!(env.state, state)
    env.action_mask[:] = obs.action_mask
end

"""
    reset!(env)

Reset the environment.

If configuration parameter lcs_always_new_seqs is set, a new set of random sequences
is created.
The intention here is to learn a more general strategy that works not just on a single
instance.
"""
function reset!(env::LCSEnvironment)::Observation
    if settings[:lcs_always_new_seqs]
        create_random_seqs!(env.inst)
    end
    env.state = LCSState(ones(Int, env.inst.m), Int[])
    fill!(env.action_mask, true)
    update_action_mask_and_p(env)
    get_observation(env)
end


"""
    step!(env, action)

Perform given action, i.e., append letter corresponding to action to solution string.

The letter/action must always be valid, which is ensured by the action_mask
component in the observations.
"""
function step!(env::LCSEnvironment, action::Int)
    done = false
    inst = env.inst
    state = env.state
    c = action  # env.action_order[action]
    append!(env.state.s, c)
    update_p(inst, state.p, c)
    update_action_mask_and_p(env)
    not_done = any(env.action_mask)
    # println("step: ", c, " appended to ", state.s, " ", not_done)
    reward_mode = settings[:lcs_reward_mode]
    if not_done
        if reward_mode === "direct"
            reward = 0.0f0
        elseif reward_mode === "smallsteps"
            reward = 0.05f0
            reward = (env.inst.external_result > 0) ?
              2.0f0 / env.inst.external_result : 0.05f0
        else
            error("Invalid reward_mode $reward_mode")
        end
        obs = get_observation(env)
    else
        if reward_mode === "direct"
            reward = Float32(length(state.s))
        elseif reward_mode === "smallsteps"
            reward = (env.inst.external_result > 0) ?
              -1.0f0 + 2.0f0 / env.inst.external_result : -1.0f0
        else
            error("Invalid reward_mode $reward_mode")
        end
        obs = Observation(
            zeros(Float32, observation_space_size(env)),
            ones(Bool, inst.sigma),
            Float32[]
        )
    end
    return obs, reward, !not_done
end

"""
    update_action_mask_and_p(env)

Update action_mask and possibly improve p by skipping exhausted letters.
"""
function update_action_mask_and_p(env::LCSEnvironment)
    inst = env.inst
    state = env.state
    for c = 1:inst.sigma
        if !env.action_mask[c]
            continue
        end
        for i = 1:inst.m
            if state.p[i] == inst.n + 1  # end of sequence reached
                fill!(env.action_mask, false)
            end
            if inst.count[i, state.p[i], c] == 0
                env.action_mask[c] = false
                break
            end
        end
    end
    for i = 1:inst.m
        si = inst.s[i]
        while state.p[i] <= length(si) && !env.action_mask[si[state.p[i]]]
            state.p[i] += 1
        end
    end
end

"""
    remaining_letter_counts(p)

Return vector indicating for each letter of the alphabet the minimum number of appearances
in the remaining strings from positions p onward.
"""
function remaining_letter_counts(env::LCSEnvironment, p::Vector{Int})
    sigma = env.inst.sigma
    counts = fill(env.inst.n, sigma)
    for i = 1:env.inst.m
        for c = 1:sigma
            count = env.inst.count[i, p[i], c]
            if count < counts[c]
                counts[c] = count
            end
        end
    end
    return counts
end

"""
    get_observation(env)

Return observation for the current state in the environment.

This is a vector consisting of:
- for each sequence the length of the remaining sequence from p onward sorted
    in non-decreasing order
- for each letter its minimum number of occurrences over all remaining sequences
    sorted in non-decreasing order
- for each letter the lengths of the remaining sequences after appending the letter
    to the partial solution, sorted according to the sequence and letter orderings from
    above
"""
function get_observation(env::LCSEnvironment)::Observation
    m = env.inst.m
    sigma = env.inst.sigma
    p = env.state.p
    s = env.inst.s
    values = Vector{Float32}(undef, observation_space_size(env))
    lengths = [length(s[i]) - p[i] + 1 for i = 1:m]
    env.seq_order = sortperm(lengths)
    values[1:m] = lengths[env.seq_order]
    counts = remaining_letter_counts(env, p)
    env.action_order = sortperm(counts)
    values[m+1:m+sigma] = counts[env.action_order] # ex counts
    idx = m + sigma + 1
    for i = env.seq_order # ex 1:m
        for c = env.action_order # ex 1:sigma
            # for each sequence (in order) and each action (in order)
            values[idx] = length(s[i]) - env.inst.succ[i, p[i], c]
            idx += 1 # TODO DANIEL Check this, but it should be ok
        end
    end
    # values are sorted according to order, priors and action_mask not!

    action_mask = copy(env.action_mask) #[env.action_order]
    # TODO Achtung: Es wird action_mask von env für die Berechnung der priors herangezogen!

    priors = env.prior_function(env, values)

    return Observation(values, action_mask, priors)
end




"""
LCS network incredients consisting of the two networks.

Attributes
- `value_nn`: network for the values
- `policy_nn`: network for the policy
- `opt_value`: ADAM-optimizer for value network
- `opt_policy`: ADAM-optimizer for policy network
"""
mutable struct LCSNetwork <: PolicyValueNetwork
    value_network::Chain
    action_network::Chain

    opt_value::ADAM
    opt_action::ADAM
end


# TODO Daniel Make the network more flexible
"""
    LCSNetwork(n_inp_value, n_inp_action, n_buffer, sigma, n_training, n_min_buffer)

Constructor for the Neural Networks. Also the Optimizer ADAM is initialized.
The policy network returns logits!

Parameters
- `n_inp_value`: number of inputs in value network
- `n_inp_policy`: number of inputs in policy network
- `sigma`: Alphabet size
"""
function LCSNetwork(n_inp_value::Int, n_inp_policy::Int, sigma::Alphabet)
    value_network = Chain(
        Dense(n_inp_value, 50, relu),
        Dense(50, 50, relu),
        Dense(50, 1, relu))
    policy_network = Chain(
        Dense(n_inp_policy, 50, relu),
        Dense(50, 50, relu),
        Dense(50, sigma, identity))
    # TODO Daniel: identity instead of relu, since softmax is used.

    opt_value = Flux.Optimise.ADAM(0.001, (0.9, 0.999))
    opt_policy = Flux.Optimise.ADAM(0.001, (0.9, 0.999))

    LCSNetwork(value_network, policy_network, opt_value, opt_policy)
end


"""
    LCSNetwork(env)

Constructor for the Neural Networks. Also the Optimizer ADAM is initialized.
All the necessary information for initializing the DeepL object are derived
from the environment.

Parameters
- `env`: the environment of the problem
"""
function LCSNetwork(env::Environment)
    # value network has only state information as input:
    # 1.) Remaining string lengths (m)
    # 2.) Minimum letter appearances (sigma)
    n_inp_value = state_space_size(env)

    # action network has observation
    n_inp_action = observation_space_size(env)

    sigma = env.inst.sigma

    LCSNetwork(n_inp_value, n_inp_action, sigma)
end


"""
    forward(network, obs_values, action_mask)

Calculate network in forward direction returning policy and value.
The provided action_mask may or may not be considered
"""
function forward(network::LCSNetwork, obs_values::Vector{Float32},
    action_mask::Vector{Bool})::Tuple{Vector{Float32}, Float32}

    policy = network.policy_network()

    # TODO Daniel: Check if Chain() returns Float32
    # TODO Daniel: Checke, ob logistische Funktion überhaupt notwendig ist (bei RELU eher nicht)

    # Normalization of policy: Policy are unmasked logits
    policy[action_mask] = typemin(Float32)
    # TODO Daniel: Klären, ob policy maskiert werden soll.
    # Wenn nicht, obige Zeile auskommentieren
    policy = softmax(policy)

    value = network.value_network()

    return policy, value
end

end  # module
