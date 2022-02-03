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

function cpu_profile_endpoint(req::HTTP.Request)
    uri = HTTP.URI(HTTP.Messages.uri(req))
    qp = HTTP.queryparams(uri)
    if isempty(qp)
        @info "TODO: interactive HTML input page"
        return HTTP.Response(400, "Need to provide query params: e.g. duration=")
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
        return _http_response(read(prof_name))
    else
        iobuf = IOBuffer()
        serialize(iobuf, data)
        return _http_response(take!(iobuf))
    end
end

function _http_response(binary_data)
    return HTTP.Response(200, ["Content-Type" => "application/octet-stream"], body = binary_data)
end

function heap_snapshot_endpoint(req::HTTP.Request)
    # TODO: implement this once https://github.com/JuliaLang/julia/pull/42286 is merged
end

function allocations_profile_endpoint(req::HTTP.Request)
    if VERSION < v"1.6.5"
        return HTTP.Response(501)
    end

    uri = HTTP.URI(HTTP.Messages.uri(req))
    qp = HTTP.queryparams(uri)
    if isempty(qp)
        @info "TODO: interactive HTML input page"
        return HTTP.Response(400, "Need to provide query params: e.g. duration=")
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
    return _http_response(read(prof_name))
end

function serve_profiling_server(;addr="127.0.0.1", port=16825)
    @info "Starting HTTP profiling server on port $port"
    HTTP.serve(addr, port) do req
        # Invoke latest for easier development with Revise.jl :)
        Base.invokelatest(_server_handler, req)
    end
end

function _server_handler(req::HTTP.Request)
    @info "DEBUG REQUEST: $(HTTP.Messages.uri(req))"

    uri = HTTP.URI(HTTP.Messages.uri(req))
    segments = HTTP.URIs.splitpath(uri)
    @assert length(segments) >= 1
    path = segments[1]

    if path == "profile"
        return cpu_profile_endpoint(req)
    elseif path == "allocs_profile"
        return allocations_profile_endpoint(req)
    end

    @info "Unsupported Path: $path"

    return HTTP.Response(404)
end

# Precompile the endpoints as much as possible, so that your /profile attempt doesn't end
# up profiling compilation!
function __init__()
    precompile(serve_profiling_server, ()) || error("precompilation of package functions is not supposed to fail")
    precompile(cpu_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
    precompile(_do_cpu_profile, (Int,Float64,Float64,Bool)) || error("precompilation of package functions is not supposed to fail")
    precompile(allocations_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
    precompile(_do_alloc_profile, (Float64,Float64,)) || error("precompilation of package functions is not supposed to fail")
end

end # module PerformanceProfilingHttpEndpoints
