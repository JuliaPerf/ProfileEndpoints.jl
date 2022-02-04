# PerformanceProfilingHttpEndpoints

Provides HTTP endpoints (and an optional an HTTP server) that wrap the profiling
functionality exposed from existing Julia packages, to allow introspecting a live-running
julia process to interrogate its performance characteristics.

Currently provides:
- `/profile` endpoint, with default query params:
    - `/profile?n=1e8&delay=0.01&duration=10&pprof=true`
- `/allocs_profile` endpoint, with default query params:
    - `/allocs_profile?sample_rate=0.0001&duration=10`


## Example

Start the server on your production process
```julia
julia> Threads.nthreads()
4

julia> t = @async PerformanceProfilingHttpEndpoints.serve_profiling_server()  # Start the profiling server in the background
[ Info: Starting HTTP profiling server on port 16825
Task (runnable) @0x0000000113c8d660

julia> for _ in 1:100 peakflops() end  # run stuff to profile (locks up the REPL)
```

Then collect a profile:
```bash
$ curl '127.0.0.1:16825/profile?duration=2&pprof=true' --output prof1.pb.gz
```

And view it in PProf:
```julia
julia> using PProf

julia> PProf.refresh(file="./prof1.pb.gz")
```
