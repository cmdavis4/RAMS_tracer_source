! Debug subroutine to output detailed heating information
! Add this to ruser.f90 if needed

! This file contains diagnostic code for debugging volumetric heating
!
! Key things to check:
! 1. Is temporal_factor being calculated correctly?
! 2. Are the spatial coordinates (bubctrx, bubctry, bubradx, bubrady) reasonable?
! 3. Is atten_length reasonable?
! 4. Is the Gaussian distribution being calculated correctly?
! 5. Are dn0 and dz_meters reasonable?
! 6. Is the conversion from W/m² to K/s correct?
!
! Expected values for the test case:
! - BTHP = 500 W/m²
! - Grid spacing = 500 m
! - Heating region: 21x21 grid points = 10.5 km x 10.5 km
! - bubradx = bubrady = 5000 m (radius to e^-1 point)
! - At center (r=0): horiz_gauss = 1.0
! - Expected heating rate at center, k=2: ~0.01-0.02 K/s
! - Over 300s: should accumulate several degrees K
