using AccuracyAtTopKernels

using Test, Distributions, LinearAlgebra, Random
import AccuracyAtTopKernels.MLKernels

include("./tests_surrogates.jl")
include("./tests_datasets.jl")
include("./tests_projections.jl")
include("./tests_primal_problems.jl")
include("./tests_dual_problems.jl")
include("./tests_kernels.jl")
include("./tests_scores.jl")


@time @testset "all tests" begin
    @testset "tests surrogates" begin
        test_hinge()
        test_quadratic()
    end

    @testset "tests datasets" begin
        test_primal()
        test_dual()
    end

    @testset "tests projections" begin
        test_projections()
    end

    @testset "tests primal problems" begin
        test_primal_problems()
    end

    @testset "tests dual problems" begin
        test_dual_problems()
    end

    @testset "tests kernels" begin
        test_kernels()
    end

    @testset "tests scores" begin
        test_scores()
    end
end;