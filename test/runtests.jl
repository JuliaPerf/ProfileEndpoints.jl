module PerformanceProfilingHttpEndpointsTests

using PerformanceProfilingHttpEndpoints
using Test
using Serialization

import InteractiveUtils
import HTTP
import Profile
import PProf

const port = 13423
const t = @async PerformanceProfilingHttpEndpoints.serve_profiling_server(;port=port)
const url = "http://127.0.0.1:$port"

@testset "PerformanceProfilingHttpEndpoints.jl" begin

    @testset "CPU profiling" begin
        done = Threads.Atomic{Bool}(false)
        # Schedule some work that's known to be expensive, to profile it
        t = @async begin
            for _ in 1:200
                if done[] return end
                InteractiveUtils.peakflops()
                yield()  # yield to allow the tests to run
            end
        end

        req = HTTP.request("GET", "$url/profile?duration=3&pprof=false")
        @test req.status == 200
        @test length(req.body) > 0

        data, lidict = deserialize(IOBuffer(req.body))
        # Test that the profile seems like valid profile data
        @test data isa Vector{UInt64}
        @test lidict isa Dict{UInt64, Vector{Base.StackTraces.StackFrame}}

        @info "Finished tests, waiting for peakflops workload to finish."
        done[] = true
        wait(t)  # handle errors
    end

    @testset "Allocation profiling" begin
        done = Threads.Atomic{Bool}(false)
        # Schedule some work that's known to be expensive, to profile it
        t = @async begin
            for _ in 1:200
                if done[] return end
                global a = [[] for i in 1:1000]
                yield()  # yield to allow the tests to run
            end
        end

        req = HTTP.request("GET", "$url/allocs_profile?duration=3", retry=false, status_exception=false)
        if !(isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))
            # We should be tesing the Allocs profiling if we're on julia nightly.
            @assert VERSION < v"1.8.0-DEV.1346"
            @test req.status == 501  # not implemented
        else
            @test req.status == 200
            @test length(req.body) > 0

            data = read(IOBuffer(req.body), String)
            # Test that there's something here
            # TODO: actually parse the profile
            @test length(data) > 100

        end
        @info "Finished tests, waiting for workload to finish."
        done[] = true
        wait(t)  # handle errors
    end

    @testset "error handling" begin
        let res = HTTP.request("GET", "$url/profile", status_exception=false)
            @test 400 <= res.status < 500
            @test res.status != 404
            # Make sure we describe how to use the endpoint
            body = String(res.body)
            @test occursin("duration", body)
            @test occursin("delay", body)
        end

        if (isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))
            let res = HTTP.request("GET", "$url/allocs_profile", status_exception=false)
                @test 400 <= res.status < 500
                @test res.status != 404
                # Make sure we describe how to use the endpoint
                body = String(res.body)
                @test occursin("duration", body)
                @test occursin("sample_rate", body)
            end
        end
    end
end

end # module PerformanceProfilingHttpEndpointsTests
