using ReTestItems, ProfileEndpoints

runtests(ProfileEndpoints, nworker_threads=2, nworkers=1, testitem_timeout=300)
