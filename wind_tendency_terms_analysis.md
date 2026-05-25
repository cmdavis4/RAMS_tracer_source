# Wind Tendency Terms in RAMS - Analysis Report

This document catalogs wind tendency terms that are calculated within RAMS during model integration. These terms contribute to the evolution of U, V, and W winds but many are not currently stored for output.

## Summary of Findings

RAMS calculates wind tendencies through several physical processes:
1. **Pressure Gradient Force** (acoustic solver)
2. **Advection** (momentum transport)
3. **Coriolis Force**
4. **Turbulent Diffusion**
5. **Buoyancy** (W only)
6. **Rayleigh Friction** (damping layer)

Most of these are computed as **contributions to the accumulated tendency arrays** (`tend%ut`, `tend%vt`, `tend%wt`) but are **not stored individually** for output.

## Currently Output Variables

### W (Vertical Wind) Budget Terms - ALREADY OUTPUT ✓

Located in [src/memory/mem_basic.f90](src/memory/mem_basic.f90):
- **WP_BUOY_THETA** - Buoyancy from virtual temperature
  - Registration: `:3:anal:mpti`
  - Calculated in: [src/core/raco.f90](src/core/raco.f90), `boyanc()` subroutine
  - Condition: `IMBUDGET >= 1`

- **WP_BUOY_COND** - Buoyancy from condensate loading
  - Registration: `:3:anal:mpti`
  - Calculated in: [src/core/raco.f90](src/core/raco.f90), `boyanc()` subroutine
  - Condition: `IMBUDGET >= 1`

- **WP_ADVDIF** - Advection + diffusion tendency for W
  - Registration: `:3:anal:mpti`
  - Calculated in: [src/core/raco.f90](src/core/raco.f90), `boyanc()` subroutine
  - Condition: `IMBUDGET >= 1`

### U Wind Terms - NEWLY ADDED ✓

- **UP_PGFORCE** - U pressure gradient force
  - Registration: `:3:anal:mpti`
  - Calculated in: [src/core/raco.f90:160-209](src/core/raco.f90#L160-L209), `prdctu()` subroutine
  - Variable name in code: `dpdx`
  - Condition: `IMBUDGET >= 1`
  - **Status: ADDED in this session**

## Tendency Terms NOT Currently Output

### 1. U Wind (Zonal) Tendencies

#### 1a. U Advection Tendency ❌ NOT OUTPUT

**Location**: [src/core/radvc.f90:143-234](src/core/radvc.f90#L143-L234)
**Subroutine**: `vel_advectc()`
**How calculated**:
```fortran
! Computes momentum fluxes first
flxu(k,i,j) = uc(k,i,j) * dn0u(k,i,j) * rtgu(i,j) * fmapui(i,j)
flxv(k,i,j) = vc(k,i,j) * dn0v(k,i,j) * rtgv(i,j) * fmapvi(i,j)
flxw(k,i,j) = wc(k,i,j) * 0.5 * (dn0(k,i,j) + dn0(k+1,i,j))

! Then computes advection contribution (lines 198-234)
! Three components: x-advection, y-advection, z-advection
ut(k,i,j) = ut(k,i,j) + [advection terms]
```

**Storage approach**:
- Compute total advection tendency before adding to `ut`
- Store as 3D temporary array
- Copy to permanent storage if `IMBUDGET >= 1`

**Complexity**: Medium - requires saving the advection calculation before it's added to `ut`

#### 1b. U Coriolis Tendency ❌ NOT OUTPUT

**Location**: [src/core/coriolis.f90:73-138](src/core/coriolis.f90#L73-L138)
**Subroutine**: `corlsu()`
**How calculated**:
```fortran
! Interpolate V to U points
vt3da(k,i,j) = (vp(k,i,j) + vp(k,i,j-jdim) +
                 vp(k,i+1,j) + vp(k,i+1,j-jdim)) * 0.25

! Apply Coriolis term (line 103-104)
ut(k,i,j) = ut(k,i,j) - vt3da(k,i,j) * (-fcor(i,j) +
             c1*(vt3da(k,i,j)*xm(i+i0) - up(k,i,j)*yt(j+j0)))

! Additional reference state term for topography (lines 111-123)
ut(k,i,j) = ut(k,i,j) - fcor(i,j) * vctr5(k)  ! or v01dn(k,ngrid)
```

**Storage approach**:
- Calculate Coriolis term separately before adding to `ut`
- Store in 3D array
- Includes both momentum and reference state components

**Complexity**: Low-Medium - straightforward to extract before adding to tendency

#### 1c. U Turbulent Diffusion Tendency ❌ NOT OUTPUT

**Location**: [src/turb/turb_diff.f90:77-171](src/turb/turb_diff.f90#L77-L171)
**Subroutine**: `diffvel()`
**How calculated**:
```fortran
! Vertical diffusion with implicit solver
! Computes vertical fluxes using eddy viscosity
vctr1(k) = cross * vt3df(k,i,j) + [vertical flux terms]

! Solves tridiagonal system for new U
! Updates tendency (lines 155-171)
ut(k,i,j) = ut(k,i,j) + dtlvi * (vt3do(k,i,j) - up(k,i,j))
             - (vt3dj(k,i,j) + vt3dk(k,i,j)) / dn0u(k,i,j)
```

**Also includes horizontal diffusion** (lines 125-147):
- Uses either Cartesian divergence or true horizontal gradients
- Depends on `IHORGRAD` setting

**Storage approach**:
- Compute diffusion tendency separately
- Requires capturing the change: `(new_u - old_u) / dt`
- Or store the flux divergence terms

**Complexity**: Medium-High - involves implicit solver, need to carefully extract tendency

#### 1d. U Rayleigh Friction ❌ NOT OUTPUT

**Location**: [src/core/raco.f90:191-194](src/core/raco.f90#L191-L194)
**Subroutine**: `rayf()` called from `prdctu()`
**When active**: `distim != 0` (damping timescale specified)
**Purpose**: Absorbing upper boundary layer

**How calculated**:
```fortran
if (distim .ne. 0.) then
   CALL rayf (1,m1,m2,m3,ia,iz,ja,jz,up,th0,dummy,rtgu,topu)
endif
```

**Storage approach**:
- Need to examine `rayf()` subroutine in [src/bc/rbnd.f90](src/bc/rbnd.f90)
- Calculate damping term before applying
- Store separately

**Complexity**: Medium - need to modify `rayf()` to return tendency

### 2. V Wind (Meridional) Tendencies

#### 2a. V Pressure Gradient Force ❌ NOT OUTPUT

**Location**: [src/core/raco.f90:218-291](src/core/raco.f90#L218-L291)
**Subroutine**: `prdctv()`
**Variable name**: `dpdy`
**How calculated**:
```fortran
allocate(dpdy(m1,m2,m3))

! Calculate pressure gradient in Y direction (lines 245-263)
dpdy(k,i,j) = -(th0(k,i,j) + th0(k,i,j+1)) * 0.5 *
              ((pp(k,i,j+1)*rtgt(i,j+1) - pp(k,i,j)*rtgt(i,j)) * dyl +
               (dpdy_top(k,i,j) - dpdy_top(k-1,i,j)) * dzt(k) * f23v(i,j))

! Use in V update (line 274)
vp(k,i,j) = vp(k,i,j) + dts * (dpdy(k,i,j) + vt(k,i,j))

deallocate(dpdy)  ! LOST!
```

**Storage approach**: Same as UP_PGFORCE
- Add `vp_pgforce` to mem_basic
- Store `dpdy` before deallocation
- Conditional on `IMBUDGET >= 1`

**Complexity**: Low - **Exactly analogous to UP_PGFORCE**

#### 2b. V Advection Tendency ❌ NOT OUTPUT

**Location**: [src/core/radvc.f90:236-279](src/core/radvc.f90#L236-L279)
**Subroutine**: `vel_advectc()` (same as U advection)
**How calculated**: Analogous to U advection with x, y, z components

**Storage approach**: Same as U advection
**Complexity**: Medium

#### 2c. V Coriolis Tendency ❌ NOT OUTPUT

**Location**: [src/core/coriolis.f90:141-204](src/core/coriolis.f90#L141-L204)
**Subroutine**: `corlsv()`
**How calculated**:
```fortran
! Interpolate U to V points
vt3da(k,i,j) = (up(k,i,j) + up(k,i-1,j) +
                 up(k,i,j+jdim) + up(k,i-1,j+jdim)) * 0.25

! Apply Coriolis term (lines 172-174)
vt(k,i,j) = vt(k,i,j) + vt3da(k,i,j) * (-fcor(i,j) +
             c1*(vt3da(k,i,j)*xt(i+i0) + vp(k,i,j)*yt(j+j0)))

! Additional reference state term (lines 181-193)
vt(k,i,j) = vt(k,i,j) + fcor(i,j) * vctr5(k)  ! or u01dn(k,ngrid)
```

**Storage approach**: Same as U Coriolis
**Complexity**: Low-Medium

#### 2d. V Turbulent Diffusion ❌ NOT OUTPUT

**Location**: [src/turb/turb_diff.f90:173-252](src/turb/turb_diff.f90#L173-L252)
**Subroutine**: `diffvel()`
**How calculated**: Analogous to U diffusion

**Storage approach**: Same as U diffusion
**Complexity**: Medium-High

#### 2e. V Rayleigh Friction ❌ NOT OUTPUT

**Location**: [src/core/raco.f90:265-268](src/core/raco.f90#L265-L268)
**When active**: `distim != 0`

**Storage approach**: Same as U Rayleigh friction
**Complexity**: Medium

### 3. W Wind (Vertical) Tendencies

#### 3a. W Pressure Gradient Force ❌ NOT OUTPUT

**Location**: [src/core/raco.f90:294-344](src/core/raco.f90#L294-L344)
**Subroutine**: `prdctw1()` and `prdctp2()`
**How calculated**:
```fortran
! Part 1: Forward part of Crank-Nicholson (prdctw1)
wp(k,i,j) = wp(k,i,j) + dts * wt(k,i,j)  ! advection/diffusion
wp(k,i,j) = wp(k,i,j) + a1da2 * acoc(k,i,j) * (pp(k,i,j) - pp(k+1,i,j))

! Part 2: Pressure gradient application (prdctp2, lines 421-425)
wp(k,i,j) = wp(k,i,j) - (pp(k+1,i,j) - pp(k,i,j)) * acoc(k,i,j)

! Final: Implicit solve (prdctw3)
```

**Complexity**: High - split between multiple subroutines, implicit/explicit time stepping

#### 3b. W Advection (part of WP_ADVDIF) ✓ PARTIALLY OUTPUT

**Status**: Already included in `WP_ADVDIF` combined with diffusion
**Location**: Computed in `advectc()`, tendency accumulated in `tend%wt`
**Could be separated**: Yes, but currently bundled with diffusion

#### 3c. W Turbulent Diffusion (part of WP_ADVDIF) ✓ PARTIALLY OUTPUT

**Status**: Already included in `WP_ADVDIF` combined with advection
**Location**: [src/turb/turb_diff.f90:253-334](src/turb/turb_diff.f90#L253-L334)
**Could be separated**: Yes, but currently bundled with advection

#### 3d. W Rayleigh Friction ❌ NOT OUTPUT

**Location**: [src/core/raco.f90:313-316](src/core/raco.f90#L313-L316)
**When active**: `distim != 0`

**Storage approach**: Same as U/V Rayleigh friction
**Complexity**: Medium

## Priority Recommendations

### Tier 1: Easiest to Implement (Low Complexity)

1. **VP_PGFORCE** - V pressure gradient force
   - **Difficulty**: ⭐ (Very Easy)
   - **Method**: Exact copy of UP_PGFORCE implementation for `dpdy`
   - **Files**: mem_basic.f90, raco.f90 (prdctv subroutine)
   - **Impact**: High - completes horizontal pressure gradient budget

2. **UP_CORIOLIS** - U Coriolis tendency
   - **Difficulty**: ⭐⭐ (Easy)
   - **Method**: Calculate Coriolis term separately before adding to `ut`
   - **Files**: mem_basic.f90, coriolis.f90 (corlsu subroutine)
   - **Impact**: High - important for balanced flows

3. **VP_CORIOLIS** - V Coriolis tendency
   - **Difficulty**: ⭐⭐ (Easy)
   - **Method**: Same as UP_CORIOLIS for V
   - **Files**: mem_basic.f90, coriolis.f90 (corlsv subroutine)
   - **Impact**: High - completes Coriolis budget

### Tier 2: Moderate Complexity

4. **UP_ADVECTION** - U advection tendency
   - **Difficulty**: ⭐⭐⭐ (Medium)
   - **Method**: Store advection calculation before adding to `ut`
   - **Files**: mem_basic.f90, radvc.f90 (vel_advectc subroutine)
   - **Notes**: Could break into U_ADV_X, U_ADV_Y, U_ADV_Z components
   - **Impact**: High - major term in momentum budget

5. **VP_ADVECTION** - V advection tendency
   - **Difficulty**: ⭐⭐⭐ (Medium)
   - **Method**: Same as UP_ADVECTION
   - **Files**: mem_basic.f90, radvc.f90 (vel_advectc subroutine)
   - **Impact**: High - major term in momentum budget

6. **UP_RAYLEIGH**, **VP_RAYLEIGH**, **WP_RAYLEIGH** - Rayleigh friction
   - **Difficulty**: ⭐⭐⭐ (Medium)
   - **Method**: Modify rayf() to return tendency separately
   - **Files**: mem_basic.f90, bc/rbnd.f90, raco.f90
   - **Impact**: Medium - only active in damping layers
   - **Condition**: `distim != 0`

### Tier 3: Higher Complexity

7. **UP_DIFFUSION** - U turbulent diffusion
   - **Difficulty**: ⭐⭐⭐⭐ (Medium-High)
   - **Method**: Extract tendency from implicit solver
   - **Files**: mem_basic.f90, turb/turb_diff.f90 (diffvel subroutine)
   - **Notes**: Involves tridiagonal solver, both vertical and horizontal
   - **Impact**: High - important for boundary layer dynamics

8. **VP_DIFFUSION** - V turbulent diffusion
   - **Difficulty**: ⭐⭐⭐⭐ (Medium-High)
   - **Method**: Same as UP_DIFFUSION
   - **Impact**: High

9. **WP_DIFFUSION** (separate from WP_ADVDIF)
   - **Difficulty**: ⭐⭐⭐ (Medium)
   - **Method**: Currently bundled, would need to separate
   - **Impact**: Medium - useful for detailed W budget

10. **WP_ADVECTION** (separate from WP_ADVDIF)
    - **Difficulty**: ⭐⭐⭐ (Medium)
    - **Method**: Currently bundled, would need to separate
    - **Impact**: Medium - useful for detailed W budget

11. **WP_PGFORCE** - W pressure gradient
    - **Difficulty**: ⭐⭐⭐⭐⭐ (High)
    - **Method**: Complex due to implicit/explicit splitting
    - **Files**: mem_basic.f90, raco.f90 (prdctw1, prdctw2, prdctp2)
    - **Notes**: Most complex due to acoustic time stepping
    - **Impact**: High - but already have WP_BUOY_* terms

## Implementation Pattern

Based on the UP_PGFORCE implementation, the pattern is:

1. **Add to mem_basic.f90**:
   ```fortran
   ! In basic_vars type
   real, allocatable, dimension(:,:,:) :: up_pgforce, vp_pgforce, [others]

   ! In alloc_basic
   if(imbudget>=1) then
      allocate (basic%up_pgforce(n1,n2,n3))
      allocate (basic%vp_pgforce(n1,n2,n3))
   endif

   ! In dealloc_basic
   if (allocated(basic%up_pgforce)) deallocate (basic%up_pgforce)
   if (allocated(basic%vp_pgforce)) deallocate (basic%vp_pgforce)

   ! In filltab_basic
   if (allocated(basic%up_pgforce)) &
      CALL vtables2 (basic%up_pgforce(1,1,1),basicm%up_pgforce(1,1,1), &
                     ng, npts, imean, 'UP_PGFORCE :3:anal:mpti')
   ```

2. **Modify calculation subroutine**:
   ```fortran
   ! Add use statements
   use mem_basic
   use micphys
   use node_mod, only:nmachs,ngrid

   ! Before deallocating temporary array
   if (imbudget >= 1) then
      basic_g(ngrid)%up_pgforce = [temporary_array]
   endif
   ```

## Summary Statistics

- **Total wind tendency terms identified**: 17
- **Currently output**: 4 (3 W terms + 1 U term newly added)
- **Not currently output**: 13
- **Easy to add (Tier 1)**: 3 terms
- **Medium complexity (Tier 2)**: 6 terms
- **Higher complexity (Tier 3)**: 4 terms

## Suggested Next Steps

**Immediate additions** (can be done quickly):
1. VP_PGFORCE (exact analog of UP_PGFORCE)
2. UP_CORIOLIS
3. VP_CORIOLIS

**After basic terms** (more involved):
4. UP_ADVECTION, VP_ADVECTION
5. UP/VP/WP_RAYLEIGH (if using damping layers)

**Research-grade budget closure** (significant effort):
6. UP/VP_DIFFUSION
7. Separate WP_ADVECTION and WP_DIFFUSION
8. WP_PGFORCE (most complex)

This would provide a complete momentum budget for research applications studying force balances and dynamics.
