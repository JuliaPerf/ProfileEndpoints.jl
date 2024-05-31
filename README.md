# ProfileEndpoints

Provides HTTP endpoints (and an optional HTTP server) that wrap the profiling
functionality exposed from existing Julia packages, to allow introspecting a live-running
Julia process to interrogate its performance characteristics.

## Endpoints

**CPU Profile**

- `/profile` endpoint to record a CPU profile for a given duration using `Profile.@profile`.
    - Default query params: `/profile?n=1e8&delay=0.01&duration=10&pprof=true`
- `/profile_start` to start the CPU profiler (without specifying a duration to run for).
    - Default query params: `/profile_start?n=1e8&delay=0.01`
- `/profile_stop` to stop the CPU profiler and return the profile.
    - Default query params: `/profile_stop?pprof=true`

**Allocation Profile**

- `/allocs_profile` endpoint to record an allocations profile for a given duration using `Profile.Allocs.@profile`.
    - Default query params: `/allocs_profile?sample_rate=0.0001&duration=10`
- `/allocs_profile_start` to start the allocation profiler (without specifying a duration to run for).
    - Default query params: `/allocs_profile_start?sample_rate=0.0001`
- `/allocs_profile_stop` to stop the allocation profiler and return the profile.
    - Takes no query params.

**Heap Snapshot**

- `/heap_snapshot` endpoint to take a heap snapshot with `Profile.take_heap_snapshot`.
    - Default query params: `/heap_snapshot?all_one=false`

**Task Backtraces**
- `/task_backtraces` endpoint to collect task backtraces. Only available in Julia v1.10+.
    - Default query params: none.

## Examples

Start the server on your production process
```julia
julia> Threads.nthreads()
4

julia> t = @async ProfileEndpoints.serve_profiling_server()  # Start the profiling server in the background
[ Info: Starting HTTP profiling server on port 16825
Task (runnable) @0x0000000113c8d660

julia> for _ in 1:100 peakflops() end  # run stuff to profile (locks up the REPL)
```

### CPU Profile

Collect a CPU profile:
```bash
$ curl '127.0.0.1:16825/profile?delay=0.01&duration=3' --output prof1.pb.gz
```

And view it in PProf:
```julia
julia> using PProf

julia> PProf.refresh(file="./prof1.pb.gz")
```

### Allocation Profile

Collect an allocation profile (requires Julia v1.8+):
```bash
$ curl '127.0.0.1:16825/allocs_profile?sample_rate=0.0001&duration=3' --output allocs_prof1.pb.gz
```

And view it in PProf:
```julia
julia> using PProf

julia> PProf.refresh(file="./allocs_prof1.pb.gz")
```

### Heap Snapshot

Take a heap snapshot (requires Julia v1.9+):
```bash
$ curl '127.0.0.1:16825/heap_snapshot?all_one=false' --output prof1.heapsnapshot
```

And upload it in the [Chrome DevTools snapshot viewer](https://developer.chrome.com/docs/devtools/memory-problems/heap-snapshots/#view_snapshots) to explore the heap.
In Chrome `View > Developer > Developer Tools`, select the `Memory` tab, and press the `Load` button to upload the file.

### Task Backtraces

Collect task backtraces (requires Julia v1.10+):
```bash
$ curl '127.0.0.1:16825/task_backtraces' --output task_backtraces.txt
```

