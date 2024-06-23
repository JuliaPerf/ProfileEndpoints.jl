using ReTestItems, ProfileEndpoints

withenv("OPENBLAS_NUM_THREADS" => "1") do
    runtests(ProfileEndpoints, nworker_threads=2, nworkers=1, testitem_timeout=300)
end
