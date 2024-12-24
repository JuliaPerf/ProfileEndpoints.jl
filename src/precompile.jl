precompile(serve_profiling_server, ()) || error("precompilation of package functions is not supposed to fail")

precompile(cpu_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(cpu_profile_start_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(cpu_profile_stop_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(wall_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(wall_profile_start_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(wall_profile_stop_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")

precompile(debug_profile_endpoint_with_stage_path, (String,)) || error("precompilation of package functions is not supposed to fail")
precompile(debug_profile_endpoint_with_stage_path, (Nothing,)) || error("precompilation of package functions is not supposed to fail")
debug_profile_endpoint_str = debug_profile_endpoint_with_stage_path("stage")
debug_profile_endpoint_nothing = debug_profile_endpoint_with_stage_path("nothing")
precompile(debug_profile_endpoint_str, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(debug_profile_endpoint_nothing, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")

precompile(heap_snapshot_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")

precompile(allocations_profile_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(allocations_start_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
precompile(allocations_stop_endpoint, (HTTP.Request,)) || error("precompilation of package functions is not supposed to fail")
if isdefined(Profile, :Allocs) && isdefined(PProf, :Allocs)
    precompile(handle_alloc_profile, (Float64,Float64,)) || error("precompilation of package functions is not supposed to fail")
    precompile(handle_alloc_profile_start, (Float64,)) || error("precompilation of package functions is not supposed to fail")
    precompile(handle_alloc_profile_stop, ()) || error("precompilation of package functions is not supposed to fail")
end
