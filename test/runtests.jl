module PerformanceProfilingHttpEndpointsTests

using PerformanceProfilingHttpEndpoints
using Test
using Serialization

import InteractiveUtils
import HTTP
import Profile

const port = 13423
const t = @async PerformanceProfilingHttpEndpoints.serve_profiling_server(;port=port)
const url = "http://127.0.0.1:$port"

@testset "PerformanceProfilingHttpEndpoints.jl" begin
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
    # Test that the profile contained at least one call to peakflops! :)
    @test length(Profile.callers("peakflops")) > 0

    @info "Finished tests, waiting for peakflops workload to finish."
    done[] = true
    wait(t)  # handle errors
end

end # module PerformanceProfilingHttpEndpointsTests
