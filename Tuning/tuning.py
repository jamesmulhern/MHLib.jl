#!/usr/bin/env python3
# Demo for using SMAC3 to optimize the configuration of a Julia algorithm.

# Ensure that Python is installed with the packages  `pyjulia`, `smac` and `ConfigSpace`


import ConfigSpace
from ConfigSpace import Configuration, ConfigurationSpace
from smac import AlgorithmConfigurationFacade, Scenario
import os
import sys

# simple way to specify a configuration space
config_space = ConfigurationSpace({
        "x": (0.1, 4.0), 
        "y": (1, 3), 
        "z":["opt1", "opt2"],
    })

# alternative long form, advanced configuration aspects possible:
config_space2 = ConfigurationSpace()
config_space2.add_hyperparameters([
    ConfigSpace.UniformFloatHyperparameter("x", 0.1, 4.0),
    ConfigSpace.UniformIntegerHyperparameter("y", 1, 3),
    ConfigSpace.CategoricalHyperparameter("z", ["opt1", "opt2"]),
])

# directory containing the problem instances; here we exemplarily just use the current one
instance_dir = "../test/data"
# names of problem instances to be used for tuning
instances = [fn for fn in os.listdir(instance_dir) if fn.startswith("maxsat")]

# features of the problem instances
# in the simplest case just the index, or otherwise some more relevant features
features = {fn: [i] for (i, fn) in enumerate(instances)}
# names of problem instances to be used for tuning

# Scenario object specifying the optimization environment
scenario = Scenario(config_space2, deterministic=False, 
                    instances=instances, instance_features=features, 
                    n_trials=200)


variant_to_use = sys.argv[1] if len(sys.argv) > 1 else "1"

if variant_to_use == "1":

    # ----- Variant 1: Call Julia function via the Python->Julia interface
    # limited to a single process/thread, but Julia is started only once

    from julia import Main
    from julia import Pkg; Pkg.activate(".")  # possibly activate correct Julia environment
    Main.include("julia-function-to-tune.jl")  # or Main.using("ModuleOrPackageToUse")

    # exemplary wrapper for Julia function to tune
    def f(config: Configuration, instance: str, seed: int) -> float:
        print(f'f({instance}, {seed}, {config["x"]}, {config["y"]}, {config["z"]})', 
              end=" -> ")
        res = Main.f(instance, seed, config["x"], config["y"], config["z"])
        print(res)
        return res
    
    smac = AlgorithmConfigurationFacade(scenario, f, overwrite=True)


elif variant_to_use == "2":

    # ----- Variant 2: Start independent Julia process for each call of function `f`
    # Allows parallelization even on the cluster, but is not very efficient if `f` is fast

    # for parallel execution in a number of Julia subprocesses:
    from dask.distributed import Client, LocalCluster

    if __name__ == "__main__":
        cluster = LocalCluster(threads_per_worker=1, n_workers=4)
        client = Client(address=cluster)

        smac = AlgorithmConfigurationFacade(scenario, 
            target_function="call-julia-function-f.jl", 
            overwrite=True, dask_client=client)

elif variant_to_use == "3":

    # ----- Variant 3: Use a number of Julia server processes to evaluate `f` repeatedly
    import julia_server
    from dask.distributed import Client, LocalCluster

    if __name__ == "__main__":
        cluster = LocalCluster(threads_per_worker=1, n_workers=4)
        client = Client(address=cluster)

        smac = AlgorithmConfigurationFacade(scenario, julia_server.f, overwrite=True,
                                            dask_client=client)

else:
    raise ValueError(f"Unknown variant, must be 1, 2, or 3: {variant_to_use}")


# -----

if __name__ == "__main__":
    incumbent = smac.optimize()
    print("Optimized configuration: ", incumbent)