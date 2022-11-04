module PerformanceProfilingHttpEndpoints

import HTTP
import Profile
import PProf

using Serialization: serialize

#----------------------------------------------------------
#  Description
#
# It would be nice if visiting the `/profile` page from a web browser gives you a form where you can:
# - configure the Profiling parameters:
#    - Set julia Profile configuration, either by:
#       - Manually setting `n` and `delay`, for `Profile.init(n, delay)`, or
#       - provide a `duration` and a `delay`, and we will compute suggested `n` and `delay` for you. (`n` is the number of stack _frames_  the profiling will hold, so it also depends on the expected stack _depth_ for each sample, and the number of threads currently running. It's good to leave a wide buffer.)
# - Export the profiling data (either with or without C-lang functions - default is `C=true`)
#   - Download the raw Julia profile data (`Profile.retrieve()`)
#   - Convert the profile data to PProf, and download it (`PProf.pprof()`)
#   - Upload the resulting profile to DataDog (as PProf profile) -- see #4937.
#
#----------------------------------------------------------

default_n() = "1e8"
default_delay() = "0.01"
default_duration() = "10.0"
default_pprof() = "true"
default_alloc_sample_rate() = "0.0001"

cpu_profile_error_message() = """Need to provide query params:
    - duration=$(default_duration())
    - delay=$(default_delay())
    - n=$(default_n())
    - pprof=$(default_pprof())

Hint: A good goal is to shoot for around 1,000 to 10,000 samples. So if you know what
duration you want to profile for, you can pick a delay via e.g. `delay = duration / 1,000`.

For example, for a 30 second profile:
30 / 1_000 = 0.03
for `duration=30&delay=0.03`

But note that if your delay gets too small, you can really slow down the program you're
profiling, and thus end up with an inaccurate profile.

If you wanted to get an extremely large number of samples (or you have very very deep stack
traces), you'll have to start worrying about filling up your julia profiling buffer,
controlled by `n=`. If you assume an average stack depth of 100, and you were aiming to get
50,000 samples, you'd need a buffer at least 50,000 * 100 big, or at least 5e6.

The default `n` is 1e8, which should be big enough for most profiles.
"""
allocs_profile_error_message() = """Need to provide query params:
    - duration=$(default_duration())
    - sample_rate=$(default_alloc_sample_rate())

Hint: A good goal is to shoot for around 1,000 to 10,000 samples. So if you know what
duration you want to profile for, and you *already have an expectation for how much your
program will allocate,* you can pick a sample_rate via `sample_rate = 1,000 / expected_allocations`.

For example, if you expect your program will actually perform 1 million allocations:
1_000 / 1_000_000 = 0.001
for `duration=30&sample_rate=0.001`

Note that if your sample_rate gets too large, you can really slow down the program you're
profiling, and thus end up with an inaccurate profile.

Finally, if you think your program only allocates a small amount, you can capture *all*
allocations by passing sample_rate=1.
"""

function cpu_profile_endpoint(req::HTTP.Request)
    uri = HTTP.URI(req.target)
    qp = HTTP.queryparams(uri)
    if isempty(qp)
        @info "TODO: interactive HTML input page"
        return HTTP.Response(400, cpu_profile_error_message())
    end

    # Run the profile
    n = convert(Int, parse(Float64, get(qp, "n", default_n())))
    delay = parse(Float64, get(qp, "delay", default_delay()))
    duration = parse(Float64, get(qp, "duration", default_duration()))
    with_pprof = parse(Bool, get(qp, "pprof", default_pprof()))

    return _do_cpu_profile(n, delay, duration, with_pprof)
end

function _do_cpu_profile(n, delay, duration, with_pprof)
    @info "Starting CPU Profiling from PerformanceProfilingHttpEndpoints with configuration:" n delay duration

    Profile.clear()

    Profile.init(n, delay)

    Profile.@profile sleep(duration)

    data = Profile.retrieve()
    if with_pprof
        prof_name = tempname()
        PProf.pprof(out=prof_name, web=false)
        prof_name = "$prof_name.pb.gz"
        return _http_response(read(prof_name),
            "cpu_profile-duration=$duration&delay=$delay&n=$n.pb.gz")
    else
        iobuf = IOBuffer()
        serialize(iobuf, data)
        return _http_response(take!(iobuf),
            "cpu_profile&duration=$duration&delay=$delay&n=$n.prof.bin")
    end
end

function _http_response(binary_data, filename)
    return HTTP.Response(200, [
        "Content-Type" => "application/octet-stream"
        "Content-Disposition" => "attachment; filename=$(repr(filename))"
    ], body = binary_data)
end

function heap_snapshot_endpoint(req::HTTP.Request)
    # TODO: implement this once https://github.com/JuliaLang/julia/pull/42286 is merged
end

@static if !(isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs))

function allocations_profile_endpoint(::HTTP.Request)
    return HTTP.Response(501, "You must use a build of Julia (1.8+) and PProf that support Allocations profiling.")
end

else

function allocations_profile_endpoint(req::HTTP.Request)

    uri = HTTP.URI(req.target)
    qp = HTTP.queryparams(uri)
    if isempty(qp)
        @info "TODO: interactive HTML input page"
        return HTTP.Response(400, allocs_profile_error_message())
    end

    sample_rate = convert(Float64, parse(Float64, get(qp, "sample_rate", default_alloc_sample_rate())))
    duration = parse(Float64, get(qp, "duration", default_duration()))

    return _do_alloc_profile(duration, sample_rate)
end

function _do_alloc_profile(duration, sample_rate)
    @info "Starting allocation Profiling from PerformanceProfilingHttpEndpoints with configuration:" duration sample_rate

    Profile.Allocs.clear()

    Profile.Allocs.@profile sample_rate=sample_rate sleep(duration)

    prof_name = tempname()
    PProf.Allocs.pprof(out=prof_name, web=false)
    prof_name = "$prof_name.pb.gz"
    return _http_response(read(prof_name),
            "allocs_profile-duration=$duration&sample_rate=$sample_rate.pb.gz")
end

end  # if isdefined

function serve_profiling_server(;addr="127.0.0.1", port=16825, verbose=false, kw...)
    verbose >= 0 && @info "Starting HTTP profiling server on port $port"
    router = HTTP.Router()
    HTTP.register!(router, "/profile", cpu_profile_endpoint)
    HTTP.register!(router, "/allocs_profile", allocations_profile_endpoint)
    # HTTP.serve! returns listening/serving server object
    return HTTP.serve!(router, addr, port; verbose, kw...)
end

# Precompile the endpoints as much as possible, so that your /profile attempt doesn't end
# up profiling compilation!
function __init__()
    precompile(serve_profiling_server, ()) || error("precompilation of package functions is not supposed to fail")
    precompile(cpu_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
    precompile(_do_cpu_profile, (Int,Float64,Float64,Bool)) || error("precompilation of package functions is not supposed to fail")
    precompile(allocations_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
    if isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs)
        precompile(_do_alloc_profile, (Float64,Float64,)) || error("precompilation of package functions is not supposed to fail")
    end
end

end # module PerformanceProfilingHttpEndpoints
