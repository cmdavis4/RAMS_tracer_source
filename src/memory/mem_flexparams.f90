!##############################################################################
Module mem_flexparams

! Generic real scalar parameters that can be set in RAMSIN and consumed
! anywhere in the source by `use mem_flexparams, only: flexparams`.
! Inspired by CM1's var1..var20. Intended for ad-hoc tuning knobs that
! do not warrant a dedicated namelist entry.

implicit none

   integer, parameter :: nflexparams = 20
   real :: flexparams(nflexparams) = 0.0

END MODULE mem_flexparams
