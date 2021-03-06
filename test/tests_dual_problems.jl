function test_dual_problems()
    n  = rand(50:100)
    m  = rand(50:100)
    X1 = rand(Normal(-1.5,1), n, 2)
    X2 = rand(Normal(1.5,1), m, 2)
    X  = vcat(X1, X2)
    y  = vcat(ones(n), zeros(m)) .== 1

    τ    = 0.2*rand() + 0.3
    K    = rand(1:10)
    C    = 0.5*rand() + 1
    ϑ1   = 0.4*rand() + 0.5
    ϑ2   = 0.5*rand() + 1

    @testset "PatMat with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l1    = surrogate(ϑ1);
        l2    = surrogate(ϑ2);
        model = PatMat(τ, C, l1, l2);
        data  = Dual(model, X, y);

        test_dual(model, data, 30000, 200000, Descent(0.001))
    end

    @testset "PatMatNP with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l1    = surrogate(ϑ1);
        l2    = surrogate(ϑ2);
        model = PatMatNP(τ, C, l1, l2);
        data  = Dual(model, X, y);

        test_dual(model, data, 30000, 200000, Descent(0.001))
    end

    @testset "TopPushK with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l     = surrogate(ϑ1);
        model = TopPushK(K, C, l);
        data  = Dual(model, X, y);

        test_dual(model, data, 30000, 200000, Descent(0.001))
    end

    @testset "TopPush with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l     = surrogate(ϑ1);
        model = TopPush(C, l);
        data  = Dual(model, X, y);

        test_dual(model, data, 30000, 200000, Descent(0.001))
    end
end


function test_dual(model::AbstractModel, data::Dual{<:DTrain}, maxiter::Integer, maxiter2::Integer, optimizer::Any; atol::Real = 1e-2)

    sol1 = solve(Gradient(maxiter = maxiter, optimizer = optimizer, verbose = false), model, data)
    L1   = AccuracyAtTopKernels.objective(model, data, sol1) 

    sol2 = solve(Coordinate(maxiter = maxiter2, verbose = false), model, data)
    L2   = AccuracyAtTopKernels.objective(model, data, sol2)
    
    sol3 = solve(General(), model, data)
    L3   = AccuracyAtTopKernels.objective(model, data, sol3)
    
    @testset "gradient solver" begin
        @testset "feasibility" begin
            isfeasible(model, data, sol1)
        end
        @testset "optimality" begin
            @test L1 ≈ L3 atol = atol
        end
    end
    @testset "coordinate solver" begin
        @testset "feasibility" begin
            isfeasible(model, data, sol2)
        end
        @testset "optimality" begin
            @test L2 ≈ L3 atol = atol
        end
    end
    @testset "general solver feasibility" begin
        isfeasible(model, data, sol3)
    end
end


function isfeasible(model::AbstractPatMat{<:Hinge}, data::Dual{<:DTrain}, solution::NamedTuple; atol::Real = 1e-5)
    α, β, δ = solution.α, solution.β, solution.δ
    @test sum(α) ≈ sum(β) atol = atol 
    @test maximum(α) <= model.l1.ϑ*model.C + atol
    @test maximum(β) <= model.l2.ϑ*δ + atol
    @test minimum(α) >= - atol
    @test minimum(β) >= - atol
end


function isfeasible(model::AbstractPatMat{<:Quadratic}, data::Dual{<:DTrain}, solution::NamedTuple; atol::Real = 1e-5)
    α, β, δ = solution.α, solution.β, solution.δ
    @test sum(α) ≈ sum(β) atol = atol
    @test minimum(α) >= - atol
    @test minimum(β) >= - atol
    @test δ >= - atol
end


function isfeasible(model::M, data::Dual{<:DTrain}, solution::NamedTuple; atol::Real = 1e-5) where {M<:AbstractTopPushK{<:Hinge}}
    α, β = solution.α, solution.β
    @test sum(α) ≈ sum(β) atol = atol
    @test maximum(α) <= model.l.ϑ*model.C + atol
    @test minimum(α) >= 0 - atol
    @test minimum(β) >= 0 - atol
    M <: TopPushK &&  @test maximum(β) <= sum(α)/model.K + atol
end


function isfeasible(model::M, data::Dual{<:DTrain}, solution::NamedTuple; atol::Real = 1e-5) where {M<:AbstractTopPushK{<:Quadratic}}
    α, β = solution.α, solution.β
    @test sum(α) ≈ sum(β) atol = atol
    @test minimum(α) >= 0 - atol
    @test minimum(β) >= 0 - atol
    M <: TopPushK && @test maximum(β) <= sum(α)/model.K + atol
end