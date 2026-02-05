# Implementation Plan: Multiple Flux Forcings System

## Overview

This plan implements a new independent flux forcing system that allows multiple separate volumetric heating forcings to be applied additively. The system will be separate from the bubble initialization code and follow the architectural pattern of the existing convergence forcing.

## Design Goals

1. Support multiple independent flux forcings (0-10)
2. Each forcing has its own spatial extent, temporal evolution, and amplitude
3. Optional random perturbations per forcing
4. Follow existing RAMS patterns (similar to convergence forcing)
5. Replace the current single IBUBBLE=5 volumetric heating with this more flexible system

## Implementation Steps

### Step 1: Add New Parameters to micphys.f90

**File**: `src/micro/micphys.f90`

**Location**: After the existing volumetric heating variables (around line 129)

**Changes**:
```fortran
!******Variables for NEW FLUX FORCING SYSTEM ************************************
integer, parameter :: max_flux_forcings = 10
integer :: nflux_forcings  ! Number of flux forcings to apply (0-10)

! Per-forcing parameters (dimensioned by max_flux_forcings)
integer, dimension(max_flux_forcings) :: iflux_grid      ! Grid number
integer, dimension(max_flux_forcings) :: iflux_xia       ! X start grid point
integer, dimension(max_flux_forcings) :: iflux_xiz       ! X end grid point
integer, dimension(max_flux_forcings) :: iflux_yja       ! Y start grid point
integer, dimension(max_flux_forcings) :: iflux_yjz       ! Y end grid point
integer, dimension(max_flux_forcings) :: iflux_k_atten   ! K level for e-folding height
real, dimension(max_flux_forcings)    :: flux_amp_wm2    ! Heating amplitude (W/m²)
integer, dimension(max_flux_forcings) :: iflux_tstart    ! Start time (s)
integer, dimension(max_flux_forcings) :: iflux_tmax      ! Max time (s)
integer, dimension(max_flux_forcings) :: iflux_tdecay    ! Decay start time (s)
integer, dimension(max_flux_forcings) :: iflux_tend      ! End time (s)
integer, dimension(max_flux_forcings) :: iflux_randpert  ! Random perturbations (0=off, 1=on)
real, dimension(max_flux_forcings)    :: flux_randamp    ! Random pert amplitude (K)
```

**Remove obsolete variables**:
- Remove IFLUXSTART, IFLUXMAX, IFLUXDECAY, IFLUXEND (replaced by per-forcing arrays)
- Keep IBUBBLE and all bubble-related parameters unchanged (those are for initialization, not continuous forcing)

**Rationale**: Centralizes all forcing-related parameters in micphys module where other physics parameters live.

---

### Step 2: Add Namelist Reading in rname.f90

**File**: `src/io/rname.f90`

**Location 1**: Add to DATA INDAT array (around line 56-81)

```fortran
DATA INDAT/  &
     ! ... existing variables ...
     ,'IFLUXEND'             &  ! Last existing flux variable
     ,'NFLUX_FORCINGS','IFLUX_GRID','IFLUX_XIA','IFLUX_XIZ'     &
     ,'IFLUX_YJA','IFLUX_YJZ','IFLUX_K_ATTEN','FLUX_AMP_WM2'    &
     ,'IFLUX_TSTART','IFLUX_TMAX','IFLUX_TDECAY','IFLUX_TEND'   &
     ,'IFLUX_RANDPERT','FLUX_RANDAMP'                           &
     ,'IRCE','RCE_SZEN'  &  ! Continue with existing variables
```

**Note**: Update the `nvindat` parameter to account for 14 new variables.

**Location 2**: Add IF blocks in nvfillm subroutine (around line 309-390)

```fortran
! After IFLUXEND (around line 308)
IF(VR.EQ.'NFLUX_FORCINGS') CALL varseti (VR,NFLUX_FORCINGS,NV,1,II,0,10)
IF(VR.EQ.'IFLUX_GRID')     CALL varseti (VR,IFLUX_GRID(NV),NV,max_flux_forcings,II,1,10)
IF(VR.EQ.'IFLUX_XIA')      CALL varseti (VR,IFLUX_XIA(NV),NV,max_flux_forcings,II,1,3000)
IF(VR.EQ.'IFLUX_XIZ')      CALL varseti (VR,IFLUX_XIZ(NV),NV,max_flux_forcings,II,1,3000)
IF(VR.EQ.'IFLUX_YJA')      CALL varseti (VR,IFLUX_YJA(NV),NV,max_flux_forcings,II,1,3000)
IF(VR.EQ.'IFLUX_YJZ')      CALL varseti (VR,IFLUX_YJZ(NV),NV,max_flux_forcings,II,1,3000)
IF(VR.EQ.'IFLUX_K_ATTEN')  CALL varseti (VR,IFLUX_K_ATTEN(NV),NV,max_flux_forcings,II,1,300)
IF(VR.EQ.'FLUX_AMP_WM2')   CALL varsetf (VR,FLUX_AMP_WM2(NV),NV,max_flux_forcings,FF,-9999.,9999.)
IF(VR.EQ.'IFLUX_TSTART')   CALL varseti (VR,IFLUX_TSTART(NV),NV,max_flux_forcings,II,0,999999)
IF(VR.EQ.'IFLUX_TMAX')     CALL varseti (VR,IFLUX_TMAX(NV),NV,max_flux_forcings,II,0,999999)
IF(VR.EQ.'IFLUX_TDECAY')   CALL varseti (VR,IFLUX_TDECAY(NV),NV,max_flux_forcings,II,0,999999)
IF(VR.EQ.'IFLUX_TEND')     CALL varseti (VR,IFLUX_TEND(NV),NV,max_flux_forcings,II,0,999999)
IF(VR.EQ.'IFLUX_RANDPERT') CALL varseti (VR,IFLUX_RANDPERT(NV),NV,max_flux_forcings,II,0,1)
IF(VR.EQ.'FLUX_RANDAMP')   CALL varsetf (VR,FLUX_RANDAMP(NV),NV,max_flux_forcings,FF,0.,10.)
```

**Location 3**: Add print output in nameout subroutine (around line 556-628)

```fortran
! After existing IFLUXEND output (around line 597)
,'NFLUX_FORCINGS=',NFLUX_FORCINGS
```

Then add grid-dependent output section for arrays:
```fortran
! After BCTAU output (around line 642)
IF (NFLUX_FORCINGS > 0) THEN
  PRINT*, ' '
  WRITE(6,*)'Flux Forcing Parameters:'
  WRITE(6,901)(' ',IFLUX_GRID(M),IFLUX_XIA(M),IFLUX_XIZ(M),M=1,NFLUX_FORCINGS)
  WRITE(6,902)(' ',IFLUX_YJA(M),IFLUX_YJZ(M),IFLUX_K_ATTEN(M),M=1,NFLUX_FORCINGS)
  WRITE(6,903)(' ',FLUX_AMP_WM2(M),IFLUX_RANDPERT(M),FLUX_RANDAMP(M),M=1,NFLUX_FORCINGS)
  WRITE(6,904)(' ',IFLUX_TSTART(M),IFLUX_TMAX(M),M=1,NFLUX_FORCINGS)
  WRITE(6,905)(' ',IFLUX_TDECAY(M),IFLUX_TEND(M),M=1,NFLUX_FORCINGS)
901  FORMAT(A1,'GRID=',I2,' XIA=',I5,' XIZ=',I5,999(A1,/,I6,2I11))
902  FORMAT(A1,' YJA=',I5,' YJZ=',I5,' K_ATTEN=',I5,999(A1,/,3I11))
903  FORMAT(A1,'AMP(W/m²)=',F8.1,' RANDPERT=',I2,' RANDAMP=',F6.2,999(A1,/,F18.1,I12,F12.2))
904  FORMAT(A1,'TSTART=',I6,' TMAX=',I6,999(A1,/,2I12))
905  FORMAT(A1,'TDECAY=',I6,' TEND=',I6,999(A1,/,2I12))
ENDIF
```

---

### Step 3: Add MPI Broadcasting in mpass_init.f90

**File**: `src/mpi/mpass_init.f90`

**Location 1**: Update buffer size calculation (around line 32)

Change:
```fortran
nwords = 223 * 1                 & !single values
```
To:
```fortran
nwords = 224 * 1                 & !single values (added NFLUX_FORCINGS)
         + 12 * max_flux_forcings & !flux forcing arrays
```

**Location 2**: Add par_put calls in broadcast_config (around line 255-258, after IFLUXEND)

```fortran
! After existing IFLUXEND (around line 258)
CALL par_put_int   (NFLUX_FORCINGS,1)
CALL par_put_int   (IFLUX_GRID,max_flux_forcings)
CALL par_put_int   (IFLUX_XIA,max_flux_forcings)
CALL par_put_int   (IFLUX_XIZ,max_flux_forcings)
CALL par_put_int   (IFLUX_YJA,max_flux_forcings)
CALL par_put_int   (IFLUX_YJZ,max_flux_forcings)
CALL par_put_int   (IFLUX_K_ATTEN,max_flux_forcings)
CALL par_put_float (FLUX_AMP_WM2,max_flux_forcings)
CALL par_put_int   (IFLUX_TSTART,max_flux_forcings)
CALL par_put_int   (IFLUX_TMAX,max_flux_forcings)
CALL par_put_int   (IFLUX_TDECAY,max_flux_forcings)
CALL par_put_int   (IFLUX_TEND,max_flux_forcings)
CALL par_put_int   (IFLUX_RANDPERT,max_flux_forcings)
CALL par_put_float (FLUX_RANDAMP,max_flux_forcings)
```

**Location 3**: Add corresponding par_get calls (find the matching section in the else block)

The par_get calls should mirror the par_put calls exactly, in the same order.

---

### Step 4: Create New Forcing Subroutines in ruser.f90

**File**: `src/surface/ruser.f90`

**Location**: After the existing volumetric_heating subroutine (after line 1013)

**New Subroutine 1**: Main driver
```fortran
!##############################################################################
Subroutine flux_forcings (tht,dn0,rtgt)

use micphys
use mem_grid, only: print_msg, time, ngrid
use node_mod, only: my_rams_num

implicit none

real, dimension(mzp,mxp,myp) :: tht,dn0
real, dimension(mxp,myp) :: rtgt

integer :: n

! Return if not using flux forcings
if(nflux_forcings <= 0) return

! Print info at initialization (only once per grid)
if(time <= 0.0 .and. print_msg .and. my_rams_num == 1) then
  print*,''
  print*,'INITIALIZING FLUX FORCING SYSTEM'
  print*,'Number of forcings =', nflux_forcings
  print*,''
endif

! Apply each forcing additively
do n = 1, nflux_forcings
  ! Only apply if this forcing is on the current grid
  if(iflux_grid(n) == ngrid) then
    CALL apply_single_flux_forcing(n, tht, dn0, rtgt)
  endif
enddo

return
END SUBROUTINE flux_forcings
```

**New Subroutine 2**: Single forcing application
```fortran
!##############################################################################
Subroutine apply_single_flux_forcing (iforcing, tht, dn0, rtgt)

use micphys
use mem_grid, only: deltax, deltaz, jdim, print_msg, time, nnxp, nnyp, xmn, ymn, zmn, ngrid
use rconstants, only: cp
use node_mod, only: my_rams_num, mxp, myp, mzp, ia, iz, ja, jz, i0, j0, mainnum, nmachs

implicit none

integer, intent(in) :: iforcing  ! Which forcing to apply (1 to nflux_forcings)
real, dimension(mzp,mxp,myp) :: tht,dn0
real, dimension(mxp,myp) :: rtgt

integer :: i,j,k
real :: bubctrx,bubctry,bubradx,bubrady,atten_length
real :: x_pos,y_pos,z_pos
real :: dist_x,dist_y,r_horiz
real :: horiz_gauss,vert_decay
real :: heating_wm2,heating_rate,base_heating
real :: temporal_factor,dz_meters
real :: max_heating_wm2,max_heating_rate,max_tendency,max_dz,max_dn0
integer :: max_i,max_j,max_k
real :: random_pert, rand_num
real, dimension(:,:), allocatable :: flux_rand_nums

! Print info at initialization
if(time <= 0.0 .and. print_msg .and. my_rams_num == 1) then
  print*,''
  print*,'FLUX FORCING #',iforcing
  print*,'On grid number=',iflux_grid(iforcing)
  print*,'Flux center from I=',iflux_xia(iforcing),'TO',iflux_xiz(iforcing)
  print*,'Flux center from J=',iflux_yja(iforcing),'TO',iflux_yjz(iforcing)
  print*,'Vertical attenuation at K=',iflux_k_atten(iforcing)
  print*,'Max heating amplitude=',flux_amp_wm2(iforcing),' W/m²'
  print*,'Flux start time=',iflux_tstart(iforcing),' s'
  print*,'Flux max time=',iflux_tmax(iforcing),' s'
  print*,'Flux decay time=',iflux_tdecay(iforcing),' s'
  print*,'Flux end time=',iflux_tend(iforcing),' s'
  if(iflux_randpert(iforcing) == 1) then
    print*,'Random perturbations ON, amplitude=',flux_randamp(iforcing),' K'
  endif
  print*,''
endif

! Calculate temporal evolution factor
if(time < real(iflux_tstart(iforcing))) then
  temporal_factor = 0.0
elseif(time >= real(iflux_tstart(iforcing)) .and. time < real(iflux_tmax(iforcing))) then
  ! Linear ramp up
  if(iflux_tmax(iforcing) > iflux_tstart(iforcing)) then
    temporal_factor = (time - real(iflux_tstart(iforcing))) / &
                      real(iflux_tmax(iforcing) - iflux_tstart(iforcing))
  else
    temporal_factor = 1.0
  endif
elseif(time >= real(iflux_tmax(iforcing)) .and. time < real(iflux_tdecay(iforcing))) then
  ! Constant maximum
  temporal_factor = 1.0
elseif(time >= real(iflux_tdecay(iforcing)) .and. time < real(iflux_tend(iforcing))) then
  ! Linear ramp down
  if(iflux_tend(iforcing) > iflux_tdecay(iforcing)) then
    temporal_factor = 1.0 - (time - real(iflux_tdecay(iforcing))) / &
                            real(iflux_tend(iforcing) - iflux_tdecay(iforcing))
  else
    temporal_factor = 0.0
  endif
else
  ! After end time
  temporal_factor = 0.0
endif

! Return if temporal factor is zero (no heating)
if(temporal_factor <= 0.0) return

! Set up X location of heating center relative to grid center
bubctrx = deltax * ((iflux_xia(iforcing) + iflux_xiz(iforcing))/2.0 - NNXP(ngrid)/2.0)
! Set up Y location of heating center relative to grid center
bubctry = deltax * ((iflux_yja(iforcing) + iflux_yjz(iforcing))/2.0 - NNYP(ngrid)/2.0)

! Set up horizontal extent (sigma in the paper)
if((iflux_xiz(iforcing) - iflux_xia(iforcing)) > 0) then
  bubradx = (iflux_xiz(iforcing) - iflux_xia(iforcing)) * deltax * 0.5
else
  bubradx = 0.0  ! Infinite in x-direction
endif

if((iflux_yjz(iforcing) - iflux_yja(iforcing)) > 0) then
  bubrady = (iflux_yjz(iforcing) - iflux_yja(iforcing)) * deltax * 0.5
else
  bubrady = 0.0  ! Infinite in y-direction
endif

! Set attenuation length for vertical decay
atten_length = ZMN(iflux_k_atten(iforcing), ngrid)

! Initialize random perturbations if needed
if(iflux_randpert(iforcing) == 1) then
  allocate(flux_rand_nums(nnxp(ngrid), nnyp(ngrid)))

  ! Generate random numbers (use same approach as bubble random perturbations)
  if((my_rams_num == mainnum) .or. (nmachs == 1)) then
    do j = 1, nnyp(ngrid)
      do i = 1, nnxp(ngrid)
        call random_number(rand_num)
        flux_rand_nums(i,j) = 1.0 - (2.0 * rand_num)  ! -1 to 1
      enddo
    enddo
  endif

  ! Broadcast if parallel
  if(nmachs > 1) then
    CALL broadcast_bub_rand_nums(nnxp(ngrid) * nnyp(ngrid), flux_rand_nums)
  endif
endif

! Initialize max tracking
max_heating_wm2 = 0.0
max_heating_rate = 0.0
max_tendency = 0.0
max_i = 0
max_j = 0
max_k = 0

! Calculate heating at each grid point
do k = 2, mzp
  do j = ja, jz
    do i = ia, iz
      ! Get grid point center coordinates
      x_pos = (XMN(i+i0,ngrid) + XMN(i+i0+1,ngrid)) * 0.5
      y_pos = (YMN(j+j0,ngrid) + YMN(j+j0+1,ngrid)) * 0.5
      z_pos = (ZMN(k,ngrid) + ZMN(k+1,ngrid)) * 0.5

      ! Calculate horizontal distance from center
      if(bubradx > 0.0) then
        dist_x = (x_pos - bubctrx) / bubradx
      else
        dist_x = 0.0
      endif

      if(bubrady > 0.0) then
        dist_y = (y_pos - bubctry) / bubrady
      else
        dist_y = 0.0
      endif

      ! For 2D simulation let Y-dir = X-dir
      if(jdim == 0) dist_y = dist_x

      ! Calculate radial distance (normalized by sigma)
      r_horiz = sqrt(dist_x**2 + dist_y**2)

      ! Horizontal Gaussian: exp(-r_normalized²)
      horiz_gauss = exp(-r_horiz**2)

      ! Vertical exponential decay
      if(atten_length > 0.0) then
        vert_decay = exp(-z_pos / atten_length)
      else
        vert_decay = 0.0
      endif

      ! Base 3D heating distribution in W/m²
      base_heating = flux_amp_wm2(iforcing) * horiz_gauss * vert_decay * temporal_factor

      ! Convert W/m² to heating rate (K/s)
      ! Formula: dT/dt = Q / (rho * dz * cp)

      ! Get layer thickness at this grid point
      dz_meters = (ZMN(k+1,ngrid) - ZMN(k,ngrid)) / rtgt(i-ia+1,j-ja+1)

      ! Calculate heating rate from base heating
      heating_rate = base_heating / (dn0(k,i-ia+1,j-ja+1) * dz_meters * cp)

      ! Add random perturbation if requested
      if(iflux_randpert(iforcing) == 1) then
        random_pert = flux_rand_nums(i+i0,j+j0) * flux_randamp(iforcing)
        heating_rate = heating_rate + random_pert / dtlt  ! Convert K to K/s
      endif

      ! Add to temperature tendency
      tht(k,i-ia+1,j-ja+1) = tht(k,i-ia+1,j-ja+1) + heating_rate

      ! Track maximum values (use base_heating for W/m² tracking)
      if(abs(base_heating) > abs(max_heating_wm2)) then
        max_heating_wm2 = base_heating
        max_heating_rate = heating_rate
        max_tendency = tht(k,i-ia+1,j-ja+1)
        max_dz = dz_meters
        max_dn0 = dn0(k,i-ia+1,j-ja+1)
        max_i = i+i0
        max_j = j+j0
        max_k = k
      endif

    enddo
  enddo
enddo

! Debug output at specific times
if(print_msg .and. my_rams_num == 1 .and. &
   (abs(time-1.0) < 0.1 .or. abs(time-300.0) < 0.1 .or. &
    abs(time-600.0) < 0.1 .or. abs(time-1200.0) < 0.1)) then
  print*,''
  print*,'FLUX FORCING #',iforcing,' DEBUG at time=',time,' s'
  print*,'  temporal_factor=',temporal_factor
  print*,'  Max heating_wm2=',max_heating_wm2,' W/m² at i,j,k=',max_i,max_j,max_k
  print*,'  Max heating_rate=',max_heating_rate,' K/s'
  print*,'  Resulting tendency=',max_tendency,' K/s'
  print*,''
endif

! Clean up random arrays
if(iflux_randpert(iforcing) == 1) then
  deallocate(flux_rand_nums)
endif

return
END SUBROUTINE apply_single_flux_forcing
```

**Important Note**: The subroutine needs access to `dtlt` for random perturbation conversion. Add to use statements:
```fortran
use mem_grid, only: deltax, deltaz, jdim, print_msg, time, nnxp, nnyp, xmn, ymn, zmn, ngrid, dtlt
```

---

### Step 5: Modify Tendency Application in rtimi.f90

**File**: `src/core/rtimi.f90`

**Location**: In subroutine tend0 (around lines 38-41)

**Replace**:
```fortran
!Volumetric heating forcing
if(IBUBBLE == 5 .and. IBUBGRD == ngrid) &
  CALL volumetric_heating (tend%tht(1),basic_g(ngrid)%dn0(1,1,1),grid_g(ngrid)%rtgt(1,1))
```

**With**:
```fortran
!Flux forcing system (replaces old IBUBBLE=5 volumetric_heating)
if(NFLUX_FORCINGS > 0) &
  CALL flux_forcings (tend%tht(1),basic_g(ngrid)%dn0(1,1,1),grid_g(ngrid)%rtgt(1,1))
```

**Rationale**: Replaces the single-forcing IBUBBLE=5 system with the new flexible multi-forcing system.

---

### Step 6: Remove Old IBUBBLE=5 References in RAMSIN

**File**: `bin.rams/RAMSIN.testrunonly`

**Location**: Around line 434-448 in $MODEL_OPTIONS

**Remove** old bubble comment that mentions IBUBBLE=5:
```fortran
   IBUBBLE = 1,              ! Bubble initialization: 0 = off
                             ! 1=square bubble, 2=gaussian bubble
                             ! 3=random perturbations (user adjust ruser.f90)
                             ! 4=surface flux forcing
                             ! 5=volumetric heating forcing
```

**Replace with**:
```fortran
   IBUBBLE = 1,              ! Bubble initialization: 0 = off
                             ! 1=square bubble, 2=gaussian bubble
                             ! 3=random perturbations (user adjust ruser.f90)
                             ! 4=combined bubble+random perturbations
                             ! (Note: volumetric heating now uses NFLUX_FORCINGS)
```

**Remove** (around line 450-454):
```fortran
!------Volumetric Heating Forcing (IBUBBLE=5) --------------------------------
   IFLUXSTART = 0,           ! Time (s) when heating starts ramping up
   IFLUXMAX   = 600,         ! Time (s) when heating reaches maximum
   IFLUXDECAY = 1200,        ! Time (s) when heating starts ramping down
   IFLUXEND   = 1800,        ! Time (s) when heating ends
```

---

### Step 7: Update RAMSIN Example Files

**File**: `bin.rams/RAMSIN.testrunonly`

**Location**: In `$MODEL_OPTIONS` section (after the convergence forcing section, around line 479)

**Add new section**:
```fortran
!------Multiple Flux Forcing System------------------------------------------
! Replaces old IBUBBLE=5 volumetric heating with more flexible system
   NFLUX_FORCINGS = 0,       ! Number of flux forcings (0-10)
                             ! Set to 0 to disable, or use values 1-10

! Only fill in arrays up to NFLUX_FORCINGS elements
! Example with 2 forcings:
!  NFLUX_FORCINGS = 2,
!  IFLUX_GRID     = 1, 1,           ! Grid for each forcing
!  IFLUX_XIA      = 5, 50,          ! X start points
!  IFLUX_XIZ      = 13, 60,         ! X end points
!  IFLUX_YJA      = 5, 50,          ! Y start points
!  IFLUX_YJZ      = 13, 60,         ! Y end points
!  IFLUX_K_ATTEN  = 16, 20,         ! K level for e-folding height
!  FLUX_AMP_WM2   = 500., 300.,     ! Heating amplitude (W/m²)
!  IFLUX_TSTART   = 0, 600,         ! Start time (s)
!  IFLUX_TMAX     = 600, 900,       ! Max time (s) - fully ramped up
!  IFLUX_TDECAY   = 1200, 1500,     ! Decay start time (s)
!  IFLUX_TEND     = 1800, 1800,     ! End time (s)
!  IFLUX_RANDPERT = 0, 1,           ! Random perturbations (0=off, 1=on)
!  FLUX_RANDAMP   = 0., 0.5,        ! Random pert amplitude (K)

   IFLUX_GRID     = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
   IFLUX_XIA      = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
   IFLUX_XIZ      = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
   IFLUX_YJA      = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
   IFLUX_YJZ      = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
   IFLUX_K_ATTEN  = 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
   FLUX_AMP_WM2   = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.,
   IFLUX_TSTART   = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   IFLUX_TMAX     = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   IFLUX_TDECAY   = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   IFLUX_TEND     = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   IFLUX_RANDPERT = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   FLUX_RANDAMP   = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.,
```

---

### Step 8: Remove Old IBUBBLE=5 Code

**File**: `src/surface/ruser.f90`

**Remove**: The entire `volumetric_heating` subroutine (lines 818-1013)

**File**: `src/micro/micphys.f90`

**Remove** (around line 129):
```fortran
!******Variables Needed for VOLUMETRIC HEATING FORCING **********************
integer :: ifluxstart,ifluxmax,ifluxdecay,ifluxend
```

**File**: `src/io/rname.f90`

**Remove from DATA INDAT**: 'IFLUXSTART','IFLUXMAX','IFLUXDECAY','IFLUXEND'

**Remove IF blocks** (around line 305-308):
```fortran
IF(VR.EQ.'IFLUXSTART')   CALL varseti (VR,IFLUXSTART,NV,1,II,0,999999)
IF(VR.EQ.'IFLUXMAX')     CALL varseti (VR,IFLUXMAX,NV,1,II,0,999999)
IF(VR.EQ.'IFLUXDECAY')   CALL varseti (VR,IFLUXDECAY,NV,1,II,0,999999)
IF(VR.EQ.'IFLUXEND')     CALL varseti (VR,IFLUXEND,NV,1,II,0,999999)
```

**Remove print statements** (around line 594-597):
```fortran
,'IFLUXSTART=',IFLUXSTART           &
,'IFLUXMAX=',IFLUXMAX               &
,'IFLUXDECAY=',IFLUXDECAY           &
,'IFLUXEND=',IFLUXEND               &
```

**File**: `src/mpi/mpass_init.f90`

**Remove par_put calls** (around line 255-258):
```fortran
CALL par_put_int   (IFLUXSTART,1)
CALL par_put_int   (IFLUXMAX,1)
CALL par_put_int   (IFLUXDECAY,1)
CALL par_put_int   (IFLUXEND,1)
```

And corresponding par_get calls in the receiving section.

**Rationale**: Clean removal of obsolete code prevents confusion and reduces maintenance burden.

**Note**: Update the `nvindat` parameter in rname.f90 to account for removing 4 variables and adding 14 new ones (net +10 variables).

---

## Testing Strategy

### Phase 1: Compilation and Basic Functionality

1. **Clean build test**
   ```bash
   cd bin.rams
   make clean
   make
   ```
   - Should compile without errors
   - Check for any warnings about array sizes or parameter mismatches

2. **Single forcing test**
   - Create RAMSIN with:
     ```
     IBUBBLE = 0  ! Disable initialization bubble
     NFLUX_FORCINGS = 1
     IFLUX_GRID(1) = 1
     IFLUX_XIA(1) = 5
     IFLUX_XIZ(1) = 13
     ! ... (complete single forcing configuration)
     ```
   - Verify heating applied correctly
   - Check temperature evolution matches expected amplitude

3. **No forcing test**
   - Set NFLUX_FORCINGS = 0
   - Run should complete normally
   - No heating should occur

### Phase 2: Multiple Forcings

4. **Two forcings, same time**
   - NFLUX_FORCINGS = 2
   - Same spatial extent, same timing
   - Total heating should be sum of both amplitudes
   - Verify with diagnostic output

5. **Two forcings, different times**
   - Forcing 1: 0-600s
   - Forcing 2: 600-1200s
   - Verify each activates/deactivates at correct times

6. **Two forcings, different locations**
   - Forcing 1: i=5-13, j=5-13
   - Forcing 2: i=20-28, j=20-28
   - Check for independent heating maxima in output

### Phase 3: Random Perturbations

7. **Random perturbations on one forcing**
   - NFLUX_FORCINGS = 1
   - IFLUX_RANDPERT(1) = 1
   - FLUX_RANDAMP(1) = 0.5
   - Verify perturbations appear in temperature field
   - Check reproducibility (should be different each run)

8. **Random perturbations on multiple forcings**
   - Both forcings have different random amplitudes
   - Verify independence of random fields

### Phase 4: Edge Cases

9. **Maximum forcings**
   - NFLUX_FORCINGS = 10
   - All with small amplitudes
   - Verify no array overflow

10. **Parallel processing**
    - Run with multiple MPI ranks
    - Verify consistent results
    - Check MPI broadcast is working

### Phase 5: Integration with Other Features

11. **Other IBUBBLE modes unaffected**
    - Test IBUBBLE=1,2,3,4 (initialization bubbles)
    - Should work as before
    - Note: IBUBBLE=5 is removed, replaced by this system

---

## Validation Checklist

Before considering implementation complete:

- [ ] Code compiles without errors or warnings
- [ ] All new parameters appear in RAMSIN output
- [ ] MPI broadcast works (parallel runs give same results as serial)
- [ ] Single forcing produces expected heating
- [ ] Multiple forcings sum correctly
- [ ] Temporal evolution works for each forcing
- [ ] Random perturbations work independently
- [ ] Old IBUBBLE=5 code and parameters removed from codebase
- [ ] Documentation updated (this file + comments in code)
- [ ] Example RAMSIN files provided

---

## Migration Notes

**Old IBUBBLE=5 system removed**: The single volumetric heating forcing (IBUBBLE=5) and its associated parameters (IFLUXSTART, IFLUXMAX, IFLUXDECAY, IFLUXEND) are completely replaced by the new NFLUX_FORCINGS system. Any existing RAMSIN files using IBUBBLE=5 will need to be updated to use the new parameters.

**Example RAMSIN for single forcing** (equivalent to old IBUBBLE=5):
```fortran
! Bubble initialization still works (IBUBBLE=1-4)
IBUBBLE = 0  ! Set to 0 for no initialization bubble

! New flux forcing system
NFLUX_FORCINGS = 1
IFLUX_GRID(1) = 1
IFLUX_XIA(1) = 5
IFLUX_XIZ(1) = 13
IFLUX_YJA(1) = 5
IFLUX_YJZ(1) = 13
IFLUX_K_ATTEN(1) = 16
FLUX_AMP_WM2(1) = 500.
IFLUX_TSTART(1) = 0
IFLUX_TMAX(1) = 600
IFLUX_TDECAY(1) = 1200
IFLUX_TEND(1) = 1800
IFLUX_RANDPERT(1) = 0
FLUX_RANDAMP(1) = 0.
```

---

## Future Enhancements (Out of Scope for Initial Implementation)

These can be added later without changing the core architecture:

1. **Moving forcings**: Add velocity parameters to translate forcing centers
2. **Moisture forcing**: Add option to force vapor tendency
3. **Momentum forcing**: Add u,v wind tendency forcing
4. **Shape options**: Beyond Gaussian (e.g., uniform, ring)
5. **Vertical structure options**: Beyond exponential decay
6. **Time-variable amplitude**: Functions instead of linear ramp
7. **Coupling to model state**: Amplitude depends on local temperature, moisture, etc.

---

## File Summary

Files to be modified:
1. `src/micro/micphys.f90` - Add new parameter declarations, remove old IBUBBLE=5 parameters
2. `src/io/rname.f90` - Add new namelist reading, remove old parameters
3. `src/mpi/mpass_init.f90` - Add new MPI broadcasting, remove old broadcasts
4. `src/surface/ruser.f90` - Add new forcing subroutines, remove volumetric_heating()
5. `src/core/rtimi.f90` - Replace IBUBBLE=5 call with new system
6. `bin.rams/RAMSIN.testrunonly` - Add new configuration, remove old IBUBBLE=5 section

New files:
- This implementation plan document

---

## Estimated Implementation Time

- Step 1 (micphys.f90): 15 minutes
- Step 2 (rname.f90): 45 minutes
- Step 3 (mpass_init.f90): 30 minutes
- Step 4 (ruser.f90): 90 minutes
- Step 5 (rtimi.f90): 5 minutes
- Step 6-7 (RAMSIN updates): 20 minutes
- Step 8 (Remove old code): 30 minutes
- Testing Phase 1-2: 2 hours
- Testing Phase 3-4: 2 hours
- **Total: ~7.5 hours** (plus debugging time)

---

## Risk Assessment

**Low Risk**:
- New code is isolated in new subroutines
- Doesn't modify existing bubble code (IBUBBLE=1-4)
- Removes obsolete IBUBBLE=5 code cleanly

**Medium Risk**:
- Array sizes in MPI broadcasting (buffer overflow if miscalculated)
- Random number generation in parallel (must broadcast correctly)

**Mitigation**:
- Test MPI broadcasting thoroughly
- Validate buffer sizes carefully
- Test parallel runs early in process

---

## Success Criteria

Implementation is successful when:

1. User can specify 2+ independent flux forcings
2. Each forcing has independent spatial, temporal, and amplitude parameters
3. Random perturbations work per forcing
4. Old IBUBBLE=5 code removed cleanly
5. Parallel runs work correctly
6. Code is well-documented with inline comments
7. Example RAMSIN configurations provided

---

## Notes

- **Parameter naming convention**: Used `IFLUX_*` prefix to match existing `IFLUX*` parameters
- **Array sizing**: `max_flux_forcings = 10` is reasonable; can be increased if needed
- **Memory impact**: Minimal - only 14 arrays * 10 elements = 140 values
- **Performance impact**: Negligible - loops only execute for active forcings
- **Code style**: Follows existing RAMS Fortran 90 conventions
