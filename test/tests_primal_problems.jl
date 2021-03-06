function test_primal_problems()
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
    data = Primal(X, y);

    @testset "PatMat with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l1    = surrogate(ϑ1);
        l2    = surrogate(ϑ2);
        model = PatMat(τ, C, l1, l2);

        test_primal(model, data, 100000, ADAM(0.0001))
    end

    @testset "PatMatNP with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l1    = surrogate(ϑ1);
        l2    = surrogate(ϑ2);
        model = PatMatNP(τ, C, l1, l2);

        test_primal(model, data, 100000, ADAM(0.0001))
    end

    @testset "TopPushK with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l     = surrogate(ϑ1);
        model = TopPushK(K, C, l);

        test_primal(model, data, 100000, ADAM())
    end

    @testset "TopPush with $surrogate loss" for surrogate in [Hinge, Quadratic] 
        l     = surrogate(ϑ1);
        model = TopPush(C, l);

        test_primal(model, data, 100000, ADAM(0.001))
    end
end


function test_primal(model::AbstractModel, data::Primal, maxiter::Integer, optimizer::Any; atol::Real = 1e-4)

    sol1 = solve(Gradient(maxiter = maxiter, optimizer = optimizer, verbose = false), model, data)
    L1   = AccuracyAtTopKernels.objective(model, data, sol1) 

    sol2 = solve(General(), model, data)
    L2   = AccuracyAtTopKernels.objective(model, data, sol2)
    
    @test L1 ≈ L2 atol = atol
end