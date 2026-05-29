The FLEXPARAMS ramsin argument allows for changing arbitrary values in the source code without needing to recompile RAMS, like the flex params in CM1. It is a 20-element real 1D array, so can only accept floating-point numbers. (It can easily be made longer than this if need be; this is the main reason I chose to implement this as an array rather than as 20 individual parameters like CM1 does.) It needs to be specified in the RAMSIN, but does not need to have all 20 values specified, it just needs at least one. If you're not using any flexparams then this value is meaningless. The values can be accessed within any subroutine by importing them via `use mem_flexparams, only: flexparams`

The purpose of this document is also to describe the particular usage of the FLEXPARAMS in the version of RAMS to which this document is attached. The use of each parameter 1-20, if used, should be described below.

1: The value of ccn1_release_start_z in mic_init.f90, which is the start of the height at which the CCN1 profile begins linearly decreasing to 0. Params 1-3 are all used in this file.
2: ccn1_release_end_z, the height at which the CCN1 profile decrease to its release value
3: ccn1_release_value, the concentration in #/mg of CCN1 above ccn1_release_end_z
4: The value of n_z_points_per_tracer in mic_init.f90, which is the number of z levels encompassed in each tracer species (used for determining vertical origins of air)
5: Height over which random initial theta perturbations (i.e. BUBBLE=3 [or BUBBLE=4 with my modifications]) linearly decrease to 0. Default RAMS value for this was 500 m. Specifically, sets random_perturbation_max_z in the `bubble` subroutine in ruser.f90.
6:
7:
8:
9:
10:
11:
12:
13:
14:
15:
16:
17:
18:
19:
20: 
