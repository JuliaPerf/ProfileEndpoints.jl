precompile(serve_profiling_server, ()) || error("precompilation of package functions is not supposed to fail")

precompile(cpu_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(cpu_profile_start_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(cpu_profile_stop_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(_do_cpu_profile, (Int,Float64,Float64,Bool)) || error("precompilation of package functions is not supposed to fail")
precompile(_start_cpu_profile, (Int,Float64,)) || error("precompilation of package functions is not supposed to fail")

precompile(heap_snapshot_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")

precompile(allocations_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(allocations_start_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(allocations_stop_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
if isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs)
    precompile(_do_alloc_profile, (Float64,Float64,)) || error("precompilation of package functions is not supposed to fail")
    precompile(_start_alloc_profile, (Float64,)) || error("precompilation of package functions is not supposed to fail")
    precompile(_stop_alloc_profile, ()) || error("precompilation of package functions is not supposed to fail")
end
