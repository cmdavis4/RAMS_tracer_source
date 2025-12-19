# Critical Bug Fix: Volumetric Heating

## The Problem
The volumetric heating implementation was producing very small temperature perturbations and weak vertical motions.

## Root Cause
**I was modifying the wrong tendency variable!**

In [src/core/rtimi.f90:41](src/core/rtimi.f90#L41), the original code was:
```fortran
CALL volumetric_heating (tend%pt(1),basic_g(ngrid)%dn0(1,1,1),basic_g(ngrid)%rtgt(1,1))
```

But `tend%pt` is the **Exner function** (pressure) tendency, NOT the potential temperature tendency!

## The Fix
Changed to use the correct variable:
```fortran
CALL volumetric_heating (tend%tht(1),basic_g(ngrid)%dn0(1,1,1),basic_g(ngrid)%rtgt(1,1))
```

From [src/memory/mem_tend.f90](src/memory/mem_tend.f90):
- `tend%pt` → Exner function tendency (allocated when `basic_g(1)%pp` exists)
- `tend%tht` → **Potential temperature tendency** (allocated when `basic_g(1)%thp` exists)

## Impact
This was causing the heating to be applied to the pressure field instead of temperature. The small perturbations observed were likely indirect effects from the incorrect pressure tendency, not the intended direct heating of the atmosphere.

With this fix, the 500 W/m² heating should produce:
- ~0.0166 K/s heating rate at the center of the forcing region
- ~5 K temperature increase after 300 seconds of full forcing
- Strong buoyancy and vertical motion development

## Additional Changes Made
Also added comprehensive debugging output to [src/surface/ruser.f90](src/surface/ruser.f90) to help diagnose issues:
- Initialization info (grid spacing, heating parameters)
- Runtime diagnostics at t=1s, 300s, 600s, 1200s showing:
  - Temporal factor
  - Heating geometry
  - Maximum heating values and locations
  - Physical parameters (density, layer thickness)
  - Verification calculations

## Next Steps
1. Recompile the code
2. Run the simulation again
3. Check for much stronger temperature perturbations and vertical motions
4. Debug output will help verify the heating is being applied correctly

## Files Modified
- [src/core/rtimi.f90](src/core/rtimi.f90#L41) - Fixed tendency variable
- [src/surface/ruser.f90](src/surface/ruser.f90) - Added debugging output
