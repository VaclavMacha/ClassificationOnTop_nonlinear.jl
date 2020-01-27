# -------------------------------------------------------------------------------
# Progress bar and State
# -------------------------------------------------------------------------------
mutable struct ProgressBar{P<:ProgressMeter.Progress, T<:Real}
    bar::P
    L0::T
    L::T
end 


struct State{S, D<:Dict, T}
    seed::S
    dict::D
    time_init::T
end 


function ProgStateInit(solver::S,
                       model::M,
                       data::D,
                       scores::AbstractVector;
                       kwargs...) where {S<:AbstractSolver, M<:AbstractModel, D<:AbstractData}

    msg  = "$(M.name) $(D.name) loss - $(S.name) solver: "
    bar  = ProgressMeter.Progress(solver.maxiter, 1, msg)
    L    = objective(model, data, values(kwargs)..., scores)
    dict = Dict{Union{Symbol, Int64}, Any}(:initial => (values(kwargs)..., time = 0, L = L))

    return State(solver.seed, dict, time()), ProgressBar(bar, L, L)
end


ProgStateInit(solver::General, model::AbstractModel, tm::Real; kwargs...) =
    State(solver.seed, Dict{Union{Symbol, Int64}, Any}(:optimal => (values(kwargs)..., time = tm)), time())


function update!(state::State,
                 progress::ProgressBar,
                 solver::AbstractSolver,
                 model::AbstractModel,
                 data::AbstractData,
                 iter::Integer,
                 scores::AbstractVector;
                 kwargs...)

    condition_1 = iter == solver.maxiter
    condition_2 = iter in solver.iters
    condition_3 = mod(iter, ceil(Int, solver.maxiter/10)) == 0 && solver.verbose

    if condition_1 || condition_2 || condition_3
        L = objective(model, data, values(kwargs)..., scores)
        progress.L = L
    end

    if solver.verbose
        ProgressMeter.next!(progress.bar; showvalues = [(:L0, progress.L0), (:L, progress.L)])
    end

    if condition_1
        state.dict[:optimal] = (values(kwargs)..., time = time() - state.time_init, L = L)
    elseif condition_2
        state.dict[iter]     = (values(kwargs)..., time = time() - state.time_init, L = L)
    end
end


# -------------------------------------------------------------------------------
# Gradient descent utilities
# -------------------------------------------------------------------------------
function minimize!(solver::AbstractSolver, x, Δ)
    Optimise.apply!(solver.optimizer, x, Δ)
    x .-= Δ
end

function maximize!(solver::AbstractSolver, x, Δ)
    Optimise.apply!(solver.optimizer, x, Δ)
    x .+= Δ
end


# -------------------------------------------------------------------------------
# Coordinate descent utilities
# -------------------------------------------------------------------------------
solution(a::Real, b::Real, Δlb::Real, Δub::Real) = min(max(Δlb, - b/a), Δub)


function update!(best::BestUpdate, k, l, Δ, L, vars)
    if L >= best.L
        best.k = k
        best.l = l
        best.Δ = Δ
        best.L = L
        best.vars = vars
    end
end


function select_rule(model::AbstractModel, data::Dual{<:DTrain}, k, args...)
    best = BestUpdate(1, 2, 0.0, -Inf, (αk = 0.0, αl = 0.0))

    for l in 1:data.n
        l == k && continue

        if k <= data.nα && l <= data.nα
            rule_αα!(model, data, best, k, l, args...)
        elseif k <= data.nα && l > data.nα
            rule_αβ!(model, data, best, k, l, args...)
        elseif k > data.nα && l <= data.nα
            rule_αβ!(model, data, best, l, k, args...)
        else
            rule_ββ!(model, data, best, k, l, args...)
        end
    end
    return best
end


function scores!(data::Dual{<:DTrain}, best::BestUpdate, s)
    if best.k <= data.nα && best.l > data.nα
        s .+= best.Δ*(data.K[:, best.k] + data.K[:, best.l])
    else 
        s .+= best.Δ*(data.K[:, best.k] - data.K[:, best.l])
    end
end


find_βmax(βsort, β, k) = βsort[1] != β[k] ? βsort[1] : βsort[2]


function find_βmax(βsort, β, k, l)
    if βsort[1] ∉ [β[k], β[l]]
        return βsort[1]
    elseif βsort[2] ∉ [β[k], β[l]]
        return βsort[2]
    else
        return βsort[3]
    end
end


function βsorted!(data::Dual{<:DTrain}, best::BestUpdate, β, βsort)
    if haskey(best.vars, :βk)
        deleteat!(βsort, searchsortedfirst(βsort, β[best.k - data.nα]; rev = true))
        insert!(βsort, searchsortedfirst(βsort, best.vars.βk; rev = true), best.vars.βk)
    end
    if haskey(best.vars, :βl)
        deleteat!(βsort, searchsortedfirst(βsort, β[best.l - data.nα]; rev = true))
        insert!(βsort, searchsortedfirst(βsort, best.vars.βl; rev = true), best.vars.βl)
    end
end


# -------------------------------------------------------------------------------
# Objective from named tuples
# -------------------------------------------------------------------------------
objective(model::AbstractModel, data::Primal, solution::NamedTuple) =
    objective(model, data, solution.w, solution.t)

objective(model::AbstractPatMat, data::Dual{<:DTrain}, solution::NamedTuple) =
    objective(model, data, solution.α, solution.β, solution.δ)

objective(model::AbstractTopPushK, data::Dual{<:DTrain}, solution::NamedTuple) =
    objective(model, data, solution.α, solution.β)


# -------------------------------------------------------------------------------
# Exact thresholds
# -------------------------------------------------------------------------------
exact_threshold(model::PatMat, data::Primal, s) =
    any(isnan.(s)) ? NaN : quantile(s, 1 - model.τ)

exact_threshold(model::PatMatNP, data::Primal, s) =
    any(isnan.(s)) ? NaN : quantile(s[data.ind_neg], 1 - model.τ)

exact_threshold(model::TopPushK, data::Primal, s) =
    mean(partialsort(s[data.ind_neg], 1:model.K, rev = true))

exact_threshold(model::TopPush, data::Primal, s) =
    maximum(s[data.ind_neg])

exact_threshold(model::AbstractModel, data::Primal, w, T) =
    exact_threshold(model, data, scores(model, data, w))

exact_threshold(model::PatMat, data::Dual{<:Union{DTrain, DValidation}}, s) =
    any(isnan.(s)) ? NaN : quantile(s, 1 - model.τ)

exact_threshold(model::PatMatNP, data::Dual{<:Union{DTrain, DValidation}}, s) =
    any(isnan.(s)) ? NaN : quantile(s[data.type.ind_neg], 1 - model.τ)

exact_threshold(model::TopPushK, data::Dual{<:Union{DTrain, DValidation}}, s) =
    mean(partialsort(s[data.type.ind_neg], 1:model.K, rev = true))

exact_threshold(model::TopPush, data::Dual{<:Union{DTrain, DValidation}}, s) =
    maximum(s[data.type.ind_neg])

exact_threshold(model::AbstractModel, data::Dual{<:Union{DTrain, DValidation}}, α, β) =
    exact_threshold(model, data, scores(model, data, α, β))