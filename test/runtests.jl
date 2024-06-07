module ProfileEndpointsTests

using ProfileEndpoints
using Serialization
using Test

import InteractiveUtils
import HTTP
import JSON3
import Profile
import PProf

const port = 13423
const stage_path = tempdir()
const server = ProfileEndpoints.serve_profiling_server(;port=port, stage_path=stage_path)
const url = "http://127.0.0.1:$port"

@testset "ProfileEndpoints.jl" begin

    @testset "CPU profiling" begin
        done = Threads.Atomic{Bool}(false)
        # Schedule some work that's known to be expensive, to profile it
        workload() = @async begin
            for _ in 1:1000
                if done[] return end
                InteractiveUtils.peakflops(1024)
                yield()  # yield to allow the tests to run
            end
        end

        @testset "profile endpoint" begin
            done[] = false
            t = workload()
            req = HTTP.get("$url/profile?duration=3&pprof=false")
            @test req.status == 200
            @test length(req.body) > 0

            data, lidict = deserialize(IOBuffer(req.body))
            # Test that the profile seems like valid profile data
            @test data isa Vector{UInt64}
            @test lidict isa Dict{UInt64, Vector{Base.StackTraces.StackFrame}}

            @info "Finished `profile` tests, waiting for peakflops workload to finish."
            done[] = true
            wait(t)  # handle errors
        end

        @testset "profile_start/stop endpoints" begin
            done[] = false
            t = workload()
            req = HTTP.get("$url/profile_start")
            @test req.status == 200
            @test String(req.body) == "CPU profiling started."

            sleep(3)  # Allow workload to run a while before we stop profiling.

            req = HTTP.get("$url/profile_stop?pprof=false")
            @test req.status == 200
            data, lidict = deserialize(IOBuffer(req.body))
            # Test that the profile seems like valid profile data
            @test data isa Vector{UInt64}
            @test lidict isa Dict{UInt64, Vector{Base.StackTraces.StackFrame}}

            @info "Finished `profile_start/stop` tests, waiting for peakflops workload to finish."
            done[] = true
            wait(t)  # handle errors

            # We retrive data via PProf directly if `pprof=true`; make sure that path's tested.
            # This second call to `profile_stop` should still return the profile, even though
            # the profiler is already stopped, as it's `profile_start` that calls `clear()`.
            req = HTTP.get("$url/profile_stop?pprof=true")
            @test req.status == 200
            # Test that there's something here
            # TODO: actually parse the profile
            data = read(IOBuffer(req.body), String)
            @test length(data) > 100
        end

        @testset "debug endpoint cpu profile" begin
            done[] = false
            t = workload()
            headers = ["Content-Type" => "application/json"]
            payload = JSON3.write(Dict("profile_type" => "cpu_profile"))
            req = HTTP.post("$url/debug_engine", headers, payload)
            @test req.status == 200
            fname = read(IOBuffer(req.body), String)
            @info "filename: $fname"
            @test isfile(fname)
        end

        @testset "debug endpoint cpu profile start/end" begin
            done[] = false
            t = workload()
            # JSON payload should contain profile_type
            headers = ["Content-Type" => "application/json"]
            payload = JSON3.write(Dict("profile_type" => "cpu_profile_start"))
            req = HTTP.post("$url/debug_engine", headers, payload)
            @test req.status == 200
            @test String(req.body) == "CPU profiling started."

            sleep(3)  # Allow workload to run a while before we stop profiling.

            payload = JSON3.write(Dict("profile_type" => "cpu_profile_stop"))
            req = HTTP.post("$url/debug_engine", headers, payload)
            @test req.status == 200
            fname = read(IOBuffer(req.body), String)
            @info "filename: $fname"
            @test isfile(fname)

            @info "Finished `debug profile_start/stop` tests, waiting for peakflops workload to finish."
            done[] = true
            wait(t)  # handle errors

            # We retrive data via PProf directly if `pprof=true`; make sure that path's tested.
            # This second call to `profile_stop` should still return the profile, even though
            # the profiler is already stopped, as it's `profile_start` that calls `clear()`.
            payload = JSON3.write(Dict("profile_type" => "cpu_profile_stop", "pprof" => "true"))
            req = HTTP.post("$url/debug_engine", headers, payload)
            @test req.status == 200
            # Test that there's something here
            # TODO: actually parse the profile
            fname = read(IOBuffer(req.body), String)
            @info "filename: $fname"
            @test isfile(fname)
        end

        @testset "Debug endpoint heap snapshot" begin
            @static if isdefined(Profile, :take_heap_snapshot)
                headers = ["Content-Type" => "application/json"]
                payload = JSON3.write(Dict("profile_type" => "heap_snapshot"))
                req = HTTP.post("$url/debug_engine", headers, payload)
                @test req.status == 200
                fname = read(IOBuffer(req.body), String)
                @info "filename: $fname"
                @test isfile(fname)
            end
        end

        @testset "Debug endpoint allocation profile" begin
            @static if isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs)
                headers = ["Content-Type" => "application/json"]
                payload = JSON3.write(Dict("profile_type" => "allocs_profile"))
                req = HTTP.post("$url/debug_engine", headers, payload)
                @test req.status == 200
                fname = read(IOBuffer(req.body), String)
                @info "filename: $fname"
                @test isfile(fname)
            end
        end

        @testset "Debug endpoint allocation profile start/stop" begin
            @static if isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs)
                headers = ["Content-Type" => "application/json"]
                payload = JSON3.write(Dict("profile_type" => "allocs_profile_start"))
                req = HTTP.post("$url/debug_engine", headers, payload)
                @test req.status == 200
                @test String(req.body) == "Allocation profiling started."

                sleep(3)  # Allow workload to run a while before we stop profiling.

                payload = JSON3.write(Dict("profile_type" => "allocs_profile_stop"))
                req = HTTP.post("$url/debug_engine", headers, payload)
                @test req.status == 200
                fname = read(IOBuffer(req.body), String)
                @info "filename: $fname"
                @test isfile(fname)
            end
        end

        @testset "Debug endpoint task backtraces" begin
            @static if VERSION >= v"1.10.0-DEV.0"
                headers = ["Content-Type" => "application/json"]
                payload = JSON3.write(Dict("profile_type" => "task_backtraces"))
                req = HTTP.post("$url/debug_engine", headers, payload)
                @test req.status == 200
                fname = read(IOBuffer(req.body), String)
                @info "filename: $fname"
                @test isfile(fname)
            end
        end

        @testset "Debug endpoint task backtraces with subdir" begin
            @static if VERSION >= v"1.10.0-DEV.0"
                headers = ["Content-Type" => "application/json"]
                payload = JSON3.write(Dict("profile_type" => "task_backtraces"))
                if !isdir(joinpath(stage_path, "foo"))
                    mkdir(joinpath(stage_path, "foo"))
                end
                req = HTTP.post("$url/debug_engine?subdir=foo", headers, payload)
                @test req.status == 200
                fname = read(IOBuffer(req.body), String)
                @info "filename: $fname"
                @test isfile(fname)
                @test occursin("foo", fname)
            end
        end
    end

    @testset "Heap snapshot $query" for query in ("", "?all_one=true")
        req = HTTP.get("$url/heap_snapshot$query", retry=false, status_exception=false)
        if !isdefined(Profile, :take_heap_snapshot)
            # Assert the version is before https://github.com/JuliaLang/julia/pull/46862
            # Although we actually also need https://github.com/JuliaLang/julia/pull/47300
            @assert VERSION < v"1.9.0-DEV.1643"
            @test req.status == 501  # not implemented
        else
            @test req.status == 200
            data = read(IOBuffer(req.body), String)
            # Test that there's something here
            # TODO: actually parse the profile
            @test length(data) > 100
        end
    end

    @testset "Allocation profiling" begin
        done = Threads.Atomic{Bool}(false)
        # Schedule some work that's known to be expensive, to profile it
        workload() = @async begin
            for _ in 1:200
                if done[] return end
                global a = [[] for i in 1:1000]
                yield()  # yield to allow the tests to run
            end
        end

        @testset "allocs_profile endpoint" begin
            done[] = false
            t = workload()
            req = HTTP.get("$url/allocs_profile?duration=3", retry=false, status_exception=false)
            if !(isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))
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
            @info "Finished `allocs_profile` tests, waiting for workload to finish."
            done[] = true
            wait(t)  # handle errors
        end

        @testset "allocs_profile_start/stop endpoints" begin
            done[] = false
            t = workload()
            req = HTTP.get("$url/allocs_profile_start", retry=false, status_exception=false)
            if !(isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))
                @assert VERSION < v"1.8.0-DEV.1346"
                @test req.status == 501  # not implemented
            else
                @test req.status == 200
                @test String(req.body) == "Allocation profiling started."
            end

            sleep(3)  # Allow workload to run a while before we stop profiling.

            req = HTTP.get("$url/allocs_profile_stop", retry=false, status_exception=false)
            if !(isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))
                @assert VERSION < v"1.8.0-DEV.1346"
                @test req.status == 501  # not implemented
            else
                @test req.status == 200
                data = read(IOBuffer(req.body), String)
                # Test that there's something here
                # TODO: actually parse the profile
                @test length(data) > 100
            end
            @info "Finished `allocs_profile_stop` tests, waiting for workload to finish."
            done[] = true
            wait(t)  # handle errors
        end
    end

    @testset "task backtraces" begin
        @testset "task_backtraces endpoint" begin
            @static if VERSION >= v"1.10.0-DEV.0"
                req = HTTP.get("$url/task_backtraces", retry=false, status_exception=false)
                @test req.status == 200
                @test length(req.body) > 0

                # Test whether the profile returned a valid file
                data = read(IOBuffer(req.body), String)
                @test isfile(data)
            end
        end
    end

    @testset "error handling" begin
        let res = HTTP.get("$url/profile", status_exception=false)
            @test 400 <= res.status < 500
            @test res.status != 404
            # Make sure we describe how to use the endpoint
            body = String(res.body)
            @test occursin("duration", body)
            @test occursin("delay", body)
        end

        if (isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))
            let res = HTTP.get("$url/allocs_profile", status_exception=false)
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

close(server)

end # module ProfileEndpointsTests
