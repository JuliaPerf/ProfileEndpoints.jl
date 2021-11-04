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

function profile_endpoint(req::HTTP.Request)
    uri = HTTP.URI(HTTP.Messages.uri(req))
    qp = HTTP.queryparams(uri)
    if isempty(qp)
        @info "interactive HTML input page"
        return HTTP.Response(400, "Need to provide query params: e.g. duration=")
    end

    # Run the profile
    n = convert(Int, parse(Float64, get(qp, "n", default_n())))
    delay = parse(Float64, get(qp, "delay", default_delay()))
    duration = parse(Float64, get(qp, "duration", default_duration()))
    with_pprof = parse(Bool, get(qp, "pprof", default_pprof()))

    return _do_profile(n, delay, duration, with_pprof)
end

function _do_profile(n, delay, duration, with_pprof)
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
    # TODO: implement this once https://github.com/JuliaLang/julia/pull/42768 is merged
end

function serve_debug_server(port=16825)
    HTTP.serve("127.0.0.1", 8087) do req
        @info "DEBUG REQUEST: $(HTTP.Messages.uri(req))"

        uri = HTTP.URI(HTTP.Messages.uri(req))
        segments = HTTP.URIs.splitpath(uri)
        @assert length(segments) >= 1
        path = segments[1]
        @info "PATH: $path"

        if (path == "profile")
            return profile_endpoint(req)
        end

        return HTTP.Response(404)
    end
end

end
