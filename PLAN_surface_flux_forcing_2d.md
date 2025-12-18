# Implementation Plan: Surface-Based Heat and Moisture Flux Forcing

## Overview
Add the ability to use surface-based heat and moisture fluxes as initial forcing, controlled by IBUBBLE=5. The fluxes will have a 2D Gaussian spatial distribution and temporal evolution controlled by four new timing parameters.

**Key Feature**: Fluxes are specified in **W/m²** (sensible and latent heat flux), matching standard meteorological conventions, then converted internally to kinematic fluxes for the surface layer scheme.

## Key Requirements
- Use existing parameters: IBDXIA, IBDXIZ, IBDYJA, IBDYJZ (spatial extent)
- Use existing parameters: BTHP, BTRP (maximum flux amplitudes)
- Add IBUBBLE=5 to enable this forcing
- Add 4 new timing parameters: IFLUXSTART, IFLUXMAX, IFLUXDECAY, IFLUXEND
- Create 2D Gaussian-shaped surface fluxes (similar to IBUBBLE=2)
- Apply fluxes in surface layer with temporal ramp-up, plateau, and ramp-down

---

## Implementation Steps

### 1. Add New Namelist Variables

**File: `src/memory/micphys.f90`**
- **Location**: Around line 126, after existing bubble variables
- **Action**: Add new integer variables for flux timing
```fortran
!******Variables Needed for BUBBLE SIMULATION ******************************
integer :: ibubble,ibubgrd,ibdxia,ibdxiz,ibdyja,ibdyjz,ibdzk1,ibdzk2
real :: bthp,brtp

!******Variables Needed for SURFACE FLUX FORCING ****************************
integer :: ifluxstart,ifluxmax,ifluxdecay,ifluxend
```

**Rationale**: These variables control the temporal evolution of surface fluxes. Keeping them with bubble variables maintains logical grouping since IBUBBLE=5 triggers this feature.

---

### 2. Update Namelist Reading

**File: `src/io/rname.f90`**

**Step 2a: Add to DATA INDAT list**
- **Location**: Line 64, in the INDAT variable list after DTHCON, DRTCON
- **Action**: Add the four new timing parameters to the namelist variable list
```fortran
DATA INDAT/  &
     ...
     ,'DTHCON','DRTCON','SLZ','SLMSTR','STGOFF','IDIFFK','IDIFFPERTS'    &
     ,'IFLUXSTART','IFLUXMAX','IFLUXDECAY','IFLUXEND'                     &
     ...
```

**Step 2b: Add variable parsing**
- **Location**: After line 303 (after BRTP parsing)
- **Action**: Add varset calls for each new parameter
```fortran
 IF(VR.EQ.'BRTP')         CALL varsetf (VR,BRTP,NV,1,FF,-1.,10.)
 IF(VR.EQ.'IFLUXSTART')   CALL varseti (VR,IFLUXSTART,NV,1,II,0,999999)
 IF(VR.EQ.'IFLUXMAX')     CALL varseti (VR,IFLUXMAX,NV,1,II,0,999999)
 IF(VR.EQ.'IFLUXDECAY')   CALL varseti (VR,IFLUXDECAY,NV,1,II,0,999999)
 IF(VR.EQ.'IFLUXEND')     CALL varseti (VR,IFLUXEND,NV,1,II,0,999999)
```

**Step 2c: Add to output listing**
- **Location**: After line 588 (after BRTP in WRITE statement)
- **Action**: Add to print output
```fortran
 ,'BRTP=',BRTP                       &
 ,'IFLUXSTART=',IFLUXSTART           &
 ,'IFLUXMAX=',IFLUXMAX               &
 ,'IFLUXDECAY=',IFLUXDECAY           &
 ,'IFLUXEND=',IFLUXEND               &
```

**Rationale**: These steps ensure the new parameters are properly read from RAMSIN, validated with appropriate ranges, and displayed in model output for verification.

---

### 3. Update MPI Broadcasting

**File: `src/mpi/mpass_init.f90`**

**Step 3a: Increment buffer size**
- **Location**: Line 32 (nwords calculation)
- **Action**: Change `219 * 1` to `223 * 1` (add 4 for new variables)
```fortran
  nwords = 223 * 1                 & !single values (was 219)
```

**Step 3b: Add par_put calls (sending node)**
- **Location**: After line 254 (after BRTP put)
- **Action**: Add broadcast for new parameters
```fortran
    CALL par_put_float (BRTP,1)
    CALL par_put_int   (IFLUXSTART,1)
    CALL par_put_int   (IFLUXMAX,1)
    CALL par_put_int   (IFLUXDECAY,1)
    CALL par_put_int   (IFLUXEND,1)
```

**Step 3c: Add par_get calls (receiving nodes)**
- **Location**: After line 588 (after BRTP get)
- **Action**: Add receive for new parameters
```fortran
    CALL par_get_float (BRTP,1)
    CALL par_get_int   (IFLUXSTART,1)
    CALL par_get_int   (IFLUXMAX,1)
    CALL par_get_int   (IFLUXDECAY,1)
    CALL par_get_int   (IFLUXEND,1)
```

**Rationale**: In parallel runs, all processors need access to these parameters. The buffer size increase and matching put/get calls ensure proper synchronization across MPI ranks.

---

### 4. Update Validation

**File: `src/io/opspec.f90`**

**Step 4a: Update IBUBBLE range check**
- **Location**: Line 715
- **Action**: Change range from 0-4 to 0-5
```fortran
IF(ibubble.lt.0 .or. ibubble.gt.5) then
   PRINT*,' FATAL - IBUBBLE must be 0, 1, 2, 3, 4, or 5'
   PRINT*,'         0 = off'
   PRINT*,'         1 = RAMSIN-set square bubble'
   PRINT*,'         2 = RAMSIN-set gaussian bubble'
   PRINT*,'         3 = Random bubble in ruser'
   PRINT*,'         4 = Combination of 2 and 3'
   PRINT*,'         5 = Surface flux forcing'
   IFATERR=IFATERR+1
ENDIF
```

**Step 4b: Add flux timing validation**
- **Location**: After line 729 (after ICONV check)
- **Action**: Add logical checks for timing sequence
```fortran
IF(ibubble.eq.5) then
   IF(ifluxstart.lt.0 .or. ifluxmax.lt.0 .or. &
      ifluxdecay.lt.0 .or. ifluxend.lt.0) then
      PRINT*,' FATAL - All flux timing parameters must be >= 0'
      IFATERR=IFATERR+1
   ENDIF
   IF(ifluxmax.lt.ifluxstart) then
      PRINT*,' FATAL - IFLUXMAX must be >= IFLUXSTART'
      IFATERR=IFATERR+1
   ENDIF
   IF(ifluxdecay.lt.ifluxmax) then
      PRINT*,' FATAL - IFLUXDECAY must be >= IFLUXMAX'
      IFATERR=IFATERR+1
   ENDIF
   IF(ifluxend.lt.ifluxdecay) then
      PRINT*,' FATAL - IFLUXEND must be >= IFLUXDECAY'
      IFATERR=IFATERR+1
   ENDIF
ENDIF
```

**Rationale**: These checks ensure the temporal sequence is logical (start → max → decay → end) and prevent runtime errors from invalid parameter combinations.

---

### 5. Implement Surface Flux Forcing Subroutine

**File: `src/surface/ruser.f90`**

**Location**: After the conv_forcing subroutine (after line 800)

**Action**: Create new subroutine `surface_flux_forcing`

```fortran
!##############################################################################
Subroutine surface_flux_forcing (m1,m2,m3,i0,j0,sflux_t,sflux_r,dn0,time)

use micphys
use mem_grid
use rconstants  ! For cp, alvl
use node_mod, only: my_rams_num, mainnum, nmachs

implicit none

integer :: m1,m2,m3,i0,j0
real, dimension(m2,m3) :: sflux_t,sflux_r,dn0  ! Added dn0 (air density at surface)
real :: time

integer :: i,j,ii,jj
real :: bubctrx,bubctry,bubradx,bubrady
real :: acetmp1,acetmp2,acetmp4,acetmp5,acetmp7,acetmp8,acetmp9
real :: sensible_flux_wm2,latent_flux_wm2,flux_t_kin,flux_r_kin,temporal_factor

! Return if not using surface flux forcing
if(ibubble.ne.5) return

! Print info at initialization
if(time.le.0.0 .and. print_msg) then
  print*,''
  print*,'INITIALIZING SURFACE FLUX FORCING (IBUBBLE=5)'
  print*,'On grid number=',IBUBGRD
  print*,'Flux center from I=',IBDXIA,'TO',IBDXIZ
  print*,'Flux center from J=',IBDYJA,'TO',IBDYJZ
  print*,'Max sensible heat flux=',BTHP,' W/m²'
  print*,'Max latent heat flux=',BRTP,' W/m²'
  print*,'Flux start time=',IFLUXSTART,' s'
  print*,'Flux max time=',IFLUXMAX,' s'
  print*,'Flux decay time=',IFLUXDECAY,' s'
  print*,'Flux end time=',IFLUXEND,' s'
  print*,''
endif

! Calculate temporal evolution factor
if(time.lt.real(ifluxstart)) then
  temporal_factor = 0.0
elseif(time.ge.real(ifluxstart) .and. time.lt.real(ifluxmax)) then
  ! Linear ramp up
  if(ifluxmax.gt.ifluxstart) then
    temporal_factor = (time - real(ifluxstart)) / real(ifluxmax - ifluxstart)
  else
    temporal_factor = 1.0
  endif
elseif(time.ge.real(ifluxmax) .and. time.lt.real(ifluxdecay)) then
  ! Constant maximum
  temporal_factor = 1.0
elseif(time.ge.real(ifluxdecay) .and. time.lt.real(ifluxend)) then
  ! Linear ramp down
  if(ifluxend.gt.ifluxdecay) then
    temporal_factor = 1.0 - (time - real(ifluxdecay)) / real(ifluxend - ifluxdecay)
  else
    temporal_factor = 0.0
  endif
else
  ! After end time
  temporal_factor = 0.0
endif

! Return if temporal factor is zero (no fluxes)
if(temporal_factor.le.0.0) return

! Set up X location of flux center relative to grid center
bubctrx = deltax * ( (IBDXIA+IBDXIZ)/2.0 - NNXP(1)/2.0 )
! Set up Y location of flux center relative to grid center
bubctry = deltax * ( (IBDYJA+IBDYJZ)/2.0 - NNYP(1)/2.0 )

! Set up length and width of flux region
if((IBDXIZ-IBDXIA).gt.0) then
  bubradx=(IBDXIZ-IBDXIA) * deltax * 0.5
else
  bubradx=0.0  ! Infinite in x-direction
endif

if((IBDYJZ-IBDYJA).gt.0) then
  bubrady=(IBDYJZ-IBDYJA) * deltax * 0.5
else
  bubrady=0.0  ! Infinite in y-direction
endif

! Set up gaussian shape (cos^2 profile like IBUBBLE=2)
acetmp8=atan(1.0)*4.0/2.0 ! pi/2

! Calculate spatially-varying fluxes
do j=1,m3
  do i=1,m2
    ! Get grid point center coordinates
    acetmp1=(XMN(i+i0,1)+XMN(i+i0+1,1))*0.5
    acetmp2=(YMN(j+j0,1)+YMN(j+j0+1,1))*0.5

    ! Calculate normalized distance from center in x
    if (bubradx.gt.0.0) then
      acetmp4=(acetmp1-bubctrx)/bubradx
      acetmp4=acetmp4**2
    else
      acetmp4=0.0  ! Infinite extent
    endif

    ! Calculate normalized distance from center in y
    if (bubrady.gt.0.0) then
      acetmp5=(acetmp2-bubctry)/bubrady
      acetmp5=acetmp5**2
    else
      acetmp5=0.0  ! Infinite extent
    endif

    ! For 2D simulation let Y-dir = X-dir
    if(jdim==0) acetmp5=acetmp4

    ! Calculate radial distance
    acetmp7=sqrt(acetmp4+acetmp5)

    ! Apply cosine-squared profile
    if(acetmp7.ge.1.0)then
      acetmp9=0.0
    else
      acetmp9=(COS(acetmp8*acetmp7))**2
    endif

    ! Apply spatial and temporal modulation to maximum flux values (W/m²)
    sensible_flux_wm2 = BTHP * acetmp9 * temporal_factor  ! W/m²
    latent_flux_wm2   = BRTP * acetmp9 * temporal_factor  ! W/m²

    ! Convert from W/m² to kinematic fluxes for surface layer scheme
    ! Sensible heat flux: Q_H / (ρ * cp) gives kinematic heat flux (K m/s)
    ! Latent heat flux:   Q_E / (ρ * L_v) gives kinematic moisture flux (kg/kg m/s)
    flux_t_kin = sensible_flux_wm2 / (dn0(i,j) * cp)     ! K m/s
    flux_r_kin = latent_flux_wm2   / (dn0(i,j) * alvl)   ! kg/kg m/s

    ! Set surface fluxes (additive to any existing fluxes)
    sflux_t(i,j) = sflux_t(i,j) + flux_t_kin
    sflux_r(i,j) = sflux_r(i,j) + flux_r_kin
  enddo
enddo

return
END SUBROUTINE surface_flux_forcing
```

**Rationale**: This subroutine follows the same spatial Gaussian pattern as IBUBBLE=2 (cos²) but applies fluxes to the surface rather than as initial perturbations. Key features:
- **Physical units**: Fluxes specified in W/m² (sensible and latent heat) matching standard meteorological conventions
- **Conversion**: Internally converts to kinematic fluxes (K m/s, kg/kg m/s) using local air density
- **Temporal evolution**: Smooth ramp-up, plateau, and ramp-down transitions
- **Typical values**: Sensible heat 50-500 W/m², latent heat 100-600 W/m² for convective conditions

---

### 6. Integrate Flux Forcing into Surface Driver

**File: `src/surface/sfc_driver.f90`**

**Step 6a: Add to surface flux calculation**
- **Location**: After line 165 (after no-soil model setup, before patch loop)
- **Action**: Call the new subroutine
```fortran
  endif

! Apply surface flux forcing if IBUBBLE=5
  if(ibubble.eq.5 .and. ngrid.eq.ibubgrd) then
    CALL surface_flux_forcing (mzp,mxp,myp,i0,j0 &
                              ,turb%sflux_t(1,1),turb%sflux_r(1,1) &
                              ,basic_g(ngrid)%dn0(2,1,1),time)
  endif

! Begin patch loop
```

**Rationale**: This placement ensures fluxes are applied after initialization of sflux_t and sflux_r (lines 156-157) but before they're used in surface layer calculations. The grid check ensures fluxes are only applied to the specified grid.

---

### 7. Update RAMSIN Template

**File: `bin.rams/RAMSIN.testrunonly`**

**Location**: After line 388 (after DRTCON)

**Action**: Add the new parameters with documentation
```fortran
   DRTCON   = 0.,            ! Constant sfc layer moist grad for no soil

!----- Surface flux forcing parameters (used when IBUBBLE=5) ----------------

   IFLUXSTART = 0,           ! Start time for surface flux forcing (seconds)
   IFLUXMAX   = 0,           ! Time when fluxes reach maximum (seconds)
   IFLUXDECAY = 0,           ! Time when fluxes begin to decay (seconds)
   IFLUXEND   = 0,           ! Time when fluxes end (seconds)

! Note: When IBUBBLE=5, surface heat and moisture fluxes are applied with:
!   - 2D Gaussian spatial distribution (like IBUBBLE=2)
!   - Spatial extent controlled by IBDXIA, IBDXIZ, IBDYJA, IBDYJZ
!   - Maximum amplitudes set by BTHP (sensible heat flux, W/m²) and
!                                  BRTP (latent heat flux, W/m²)
!   - Fluxes are converted internally to kinematic fluxes using air density
!   - Typical values: BTHP = 50-500 W/m², BRTP = 100-600 W/m²
!   - Temporal evolution:
!       * Linear increase from 0 (at IFLUXSTART) to max (at IFLUXMAX)
!       * Constant at maximum (from IFLUXMAX to IFLUXDECAY)
!       * Linear decrease to 0 (from IFLUXDECAY to IFLUXEND)
```

**Rationale**: Comprehensive documentation in the template helps users understand how to use the new feature correctly.

---

## Key Design Decisions

### 1. **Reuse Existing Parameters with Physical Units**
- IBDXIA, IBDXIZ, IBDYJA, IBDYJZ: Already control spatial extent for bubbles
- BTHP, BRTP: Repurposed as **W/m²** (sensible and latent heat flux)
  - More intuitive than kinematic fluxes
  - Matches standard meteorological measurements
  - Easy to relate to observational data
- Minimizes namelist changes and maintains consistency with existing features

### 2. **2D Gaussian Shape (cos² profile)**
- Matches IBUBBLE=2 implementation
- Provides smooth spatial distribution
- Prevents artificial discontinuities at flux boundaries

### 3. **W/m² to Kinematic Flux Conversion**
- Input: Fluxes in W/m² (energy flux)
- Conversion uses local air density at surface (dn0)
- Sensible heat: `Q_H / (ρ * c_p)` → K m/s
- Latent heat: `Q_E / (ρ * L_v)` → kg/kg m/s
- Accounts for density variations (altitude, temperature)
- Constants: c_p ≈ 1004 J/(kg·K), L_v ≈ 2.5×10⁶ J/kg from rconstants

### 4. **Additive Fluxes**
- `sflux_t(i,j) = sflux_t(i,j) + flux_t_kin`
- Allows combination with other surface flux mechanisms (DTHCON, LEAF3, etc.)
- More flexible than replacement approach

### 5. **Temporal Evolution**
- Four distinct phases: ramp-up, plateau, ramp-down, off
- Linear transitions ensure smooth forcing
- Flexible timing allows various experimental designs

### 6. **Application Location**
- Applied in `sfc_driver.f90` before patch calculations
- Ensures fluxes feed into all subsequent surface layer physics
- Maintains proper interaction with boundary layer scheme

---

## Testing Strategy

### Unit Tests
1. **Namelist reading**: Verify all four new parameters are read correctly
2. **MPI broadcast**: Confirm values match across all processors
3. **Validation**: Test error catching for invalid timing sequences

### Functional Tests
1. **Unit conversion**:
   - Verify W/m² to kinematic flux conversion is correct
   - Test with known density: ρ = 1.2 kg/m³, Q_H = 240 W/m² → flux ≈ 0.2 K m/s
   - Check that conversion uses local density (varies with altitude/temperature)

2. **Spatial distribution**:
   - Set all times to same value (constant forcing)
   - Verify 2D Gaussian shape matches IBUBBLE=2 pattern
   - Test infinite extent (IBDXIA=IBDXIZ or IBDYJA=IBDYJZ)

3. **Temporal evolution**:
   - Verify zero flux before IFLUXSTART
   - Check linear ramp from IFLUXSTART to IFLUXMAX
   - Confirm constant flux from IFLUXMAX to IFLUXDECAY
   - Verify linear decay from IFLUXDECAY to IFLUXEND
   - Confirm zero flux after IFLUXEND

4. **Integration**:
   - Test with ISFCL=0 (no soil model - uses DTHCON/DRTCON)
   - Test with ISFCL=1 (LEAF3)
   - Verify fluxes combine correctly with existing mechanisms

### Comparison Tests
- Compare W/m² specification with manually-calculated kinematic fluxes
- Verify energy conservation (input W/m² matches heating rate in boundary layer)
- Compare with typical observed surface flux values (daytime convection, stable boundary layer)
- Test response for realistic flux values (sensible 100-300 W/m², latent 200-400 W/m²)
- Verify atmospheric response is physically reasonable (triggers convection if strong enough)

---

## Potential Extensions (Future Work)

1. **Variable Decay Rates**: Allow different ramp-up vs ramp-down timescales
2. **Vertical Distribution**: Extend fluxes over multiple surface layers
3. **Multiple Flux Centers**: Support arrays of flux locations
4. **Diurnal Forcing**: Add sinusoidal temporal variation option
5. **Grid-Dependent Timing**: Allow different timings for nested grids
6. **Bowen Ratio Mode**: Specify total flux and Bowen ratio instead of separate sensible/latent

---

## Example Usage

### Typical Convective Case
```fortran
! In RAMSIN:
IBUBBLE = 5              ! Enable surface flux forcing
IBUBGRD = 1              ! Apply to grid 1

! Horizontal extent (50 km diameter circle)
IBDXIA = 40              ! Start at grid point 40
IBDXIZ = 60              ! End at grid point 60
IBDYJA = 40
IBDYJZ = 60

! Flux amplitudes (W/m²)
BTHP = 250.0             ! Sensible heat flux (moderate daytime)
BRTP = 350.0             ! Latent heat flux (moist surface)

! Temporal evolution (1-hour simulation)
IFLUXSTART = 0           ! Start immediately
IFLUXMAX = 1800          ! Reach max at 30 min
IFLUXDECAY = 2700        ! Begin decay at 45 min
IFLUXEND = 3600          ! End at 1 hour
```

This creates a localized surface heat source that:
- Spans 20 grid points (≈50 km at 2.5 km resolution)
- Provides moderate convective forcing
- Gradually turns on/off to avoid shocks

---

## Files Modified Summary

| File | Purpose | Lines Changed |
|------|---------|---------------|
| `src/memory/micphys.f90` | Add variable declarations | ~2 lines |
| `src/io/rname.f90` | Namelist reading & output | ~15 lines |
| `src/mpi/mpass_init.f90` | MPI broadcasting | ~9 lines |
| `src/io/opspec.f90` | Validation checks | ~20 lines |
| `src/surface/ruser.f90` | New flux subroutine | ~150 lines |
| `src/surface/sfc_driver.f90` | Integration point | ~4 lines |
| `bin.rams/RAMSIN.testrunonly` | Documentation | ~15 lines |

**Total**: ~215 lines of new/modified code

---

## Dependencies

### Existing Code Dependencies
- Relies on existing grid coordinate arrays (XMN, YMN)
- Uses existing deltax, jdim, NNXP, NNYP
- Requires rconstants module for cp (specific heat) and alvl (latent heat of vaporization)
- Needs access to basic_g(ngrid)%dn0 (air density at surface)
- Integrates with existing turb%sflux_t and turb%sflux_r arrays

### No Breaking Changes
- Backward compatible: IBUBBLE=0-4 behavior unchanged
- Default values (all zeros) maintain current behavior
- Existing RAMSIN files work without modification

---

## Timeline Estimate

1. **Variable declarations & namelist** (30 min): Steps 1-3
2. **Validation** (15 min): Step 4
3. **Core implementation** (1-2 hours): Step 5
4. **Integration** (30 min): Step 6
5. **Documentation** (15 min): Step 7
6. **Testing** (1-2 hours): Unit and functional tests
7. **Debugging/Refinement** (1-2 hours): Address any issues

**Total**: 4-7 hours for complete implementation and testing
