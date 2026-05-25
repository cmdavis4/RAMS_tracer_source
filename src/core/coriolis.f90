!##############################################################################
Subroutine fcorio (n2,n3,fcoru,fcorv,glat)

use mem_grid
use rconstants

implicit none

integer :: n2,n3
real, dimension(n2,n3) :: fcoru,fcorv,glat

!    +----------------------------------------------------------------+
!    \  This routine calculates the Coriolis parameter.
!    +----------------------------------------------------------------+

real :: omega2
integer :: i,j

omega2 = 2. * omega

do j = 1,max(1,n3-1)
   do i = 1,n2-1
      fcoru(i,j) = omega2*sin((glat(i,j)+glat(i+1,j))  &
           *.5*pi180)
      fcorv(i,j) = omega2*sin((glat(i,j)+glat(i,j+jdim))  &
           *.5*pi180)
   enddo
enddo

return
END SUBROUTINE fcorio

!##############################################################################
Subroutine corlos (mzp,mxp,myp,i0,j0,ia,iz,ja,jz,izu,jzv)

use mem_basic
use mem_grid
use mem_scratch
use mem_tend

implicit none

integer :: mzp,mxp,myp,i0,j0,ia,iz,ja,jz,izu,jzv

!     This routine is the coriolis driver.  Its purpose is to compute
!     coriolis accelerations for u and v and add them into
!     the accumulated tendency arrays of UT and VT.

if(icorflg.eq.0) return

CALL corlsu (mzp,mxp,myp,i0,j0,ia,izu,ja,jz  &
     ,basic_g(ngrid)%uc(1,1,1)   &
     ,basic_g(ngrid)%vc(1,1,1)   &
     ,tend%ut(1)                 &
     ,scratch%scr1(1)            &
     ,grid_g(ngrid)%topu(1,1)    &
     ,grid_g(ngrid)%rtgu(1,1)    &
     ,basic_g(ngrid)%fcoru(1,1)  )

CALL corlsv (mzp,mxp,myp,i0,j0,ia,iz,ja,jzv  &
     ,basic_g(ngrid)%uc(1,1,1)   &
     ,basic_g(ngrid)%vc(1,1,1)   &
     ,tend%vt(1)                 &
     ,scratch%scr1(1)            &
     ,grid_g(ngrid)%topv(1,1)    &
     ,grid_g(ngrid)%rtgv(1,1)    &
     ,basic_g(ngrid)%fcorv(1,1)  )

return
END SUBROUTINE corlos

!##############################################################################
Subroutine corlsu (m1,m2,m3,i0,j0,ia,iz,ja,jz,up,vp,ut,vt3da,top,rtg,fcor)

use mem_grid
use rconstants
use mem_scratch
use ref_sounding
use mem_basic
use io_params, only: iuvwtend

implicit none

integer :: m1,m2,m3,i0,j0,ia,iz,ja,jz
real, dimension(m1,m2,m3) :: up,vp,ut,vt3da
real, dimension(m2,m3) ::    top,rtg,fcor
real :: coriolis_contribution, coriolis_contribution2

integer :: i,j,k
real :: c1
real, dimension(:,:,:), allocatable :: cor_term

! Allocate and initialize array to accumulate Coriolis tendency
if(iuvwtend>=1) then
  allocate(cor_term(m1,m2,m3))
  cor_term = 0.0
endif

do j=ja,jz
   do i=ia,iz
      do k=2,m1-1
         vt3da(k,i,j)=(vp(k,i,j)+vp(k,i,j-jdim)  &
              +vp(k,i+1,j)+vp(k,i+1,j-jdim))*.25
      enddo
   enddo
enddo

c1=1./(erad*erad*2.)
if(ihtran.eq.0) c1=0.
do j=ja,jz
   do i=ia,iz
      do k=2,m1-1
         ! Calculate Coriolis term
         coriolis_contribution = -vt3da(k,i,j)*(-fcor(i,j)  &
                  +c1*(vt3da(k,i,j)*xm(i+i0)-up(k,i,j)*yt(j+j0)))

         ! Add to tendency
         ut(k,i,j)=ut(k,i,j) + coriolis_contribution

         ! Store for budget diagnostics
         if(iuvwtend>=1) then
           cor_term(k,i,j) = cor_term(k,i,j) + coriolis_contribution
         endif
      enddo
   enddo
enddo

if (initial == 2 .or. (initial == 3 .and. initorig == 2)) then
  ! Store Coriolis term before early return
  if(iuvwtend>=1) then
    basic_g(ngrid)%up_coriolis(1:m1,1:m2,1:m3) = cor_term(1:m1,1:m2,1:m3)
    deallocate(cor_term)
  endif
  return
endif

if (itopo == 1) then

   do j = ja,jz
      do i = ia,iz
         do k = 1,m1
            vctr2(k) = zt(k) * rtg(i,j) + top(i,j)
         enddo
         CALL htint (nzp,v01dn(1,ngrid),zt,nz,vctr5,vctr2)
         do k = 2,m1-1
            coriolis_contribution2 = - fcor(i,j) * vctr5(k)
            ut(k,i,j) = ut(k,i,j) + coriolis_contribution2
            if(iuvwtend>=1) then
              cor_term(k,i,j) = cor_term(k,i,j) + coriolis_contribution2
            endif
         enddo
      enddo
   enddo

else

   do j = ja,jz
      do i = ia,iz
         do k = 2,m1-1
            coriolis_contribution2 = - fcor(i,j) * v01dn(k,ngrid)
            ut(k,i,j) = ut(k,i,j) + coriolis_contribution2
            if(iuvwtend>=1) then
              cor_term(k,i,j) = cor_term(k,i,j) + coriolis_contribution2
            endif
         enddo
      enddo
   enddo

endif

! Store accumulated Coriolis term for budget diagnostics
if(iuvwtend>=1) then
  basic_g(ngrid)%up_coriolis(1:m1,1:m2,1:m3) = cor_term(1:m1,1:m2,1:m3)
  deallocate(cor_term)
endif

return
END SUBROUTINE corlsu

!##############################################################################
Subroutine corlsv (m1,m2,m3,i0,j0,ia,iz,ja,jz,up,vp,vt,vt3da,top,rtg,fcor)

use mem_grid
use rconstants
use mem_scratch
use ref_sounding
use mem_basic
use io_params, only: iuvwtend

implicit none

integer :: m1,m2,m3,i0,j0,ia,iz,ja,jz
real, dimension(m1,m2,m3) :: up,vp,vt3da,vt
real, dimension(m2,m3) ::    top,rtg,fcor

integer :: i,j,k
real :: c1
real, dimension(:,:,:), allocatable :: cor_term
real :: coriolis_contribution, coriolis_contribution2

!       This routine calculates coriolis tendencies to v

! Allocate and initialize array to accumulate Coriolis tendency
if(iuvwtend>=1) then
  allocate(cor_term(m1,m2,m3))
  cor_term = 0.0
endif

do j = ja,jz
   do i = ia,iz
      do k = 2,m1-1
         vt3da(k,i,j) = (up(k,i,j) + up(k,i-1,j)  &
            + up(k,i,j+jdim) + up(k,i-1,j+jdim)) * .25
      enddo
   enddo
enddo

c1 = 1. / (erad * erad * 2.)
if (ihtran .eq. 0) c1 = 0.
do j = ja,jz
   do i = ia,iz
      do k = 2,m1-1
         ! Calculate Coriolis term
         coriolis_contribution = - vt3da(k,i,j) * (fcor(i,j)  &
            - c1 * (vp(k,i,j) * xt(i+i0) - vt3da(k,i,j) * ym(j+j0)))

         ! Add to tendency
         vt(k,i,j) = vt(k,i,j) + coriolis_contribution

         ! Store for budget diagnostics
         if(iuvwtend>=1) then
           cor_term(k,i,j) = cor_term(k,i,j) + coriolis_contribution
         endif
      enddo
   enddo
enddo

if (initial == 2 .or. (initial == 3 .and. initorig == 2)) then
  ! Store Coriolis term before early return
  if(iuvwtend>=1) then
    basic_g(ngrid)%vp_coriolis(1:m1,1:m2,1:m3) = cor_term(1:m1,1:m2,1:m3)
    deallocate(cor_term)
  endif
  return
endif

if (itopo == 1) then

   do j = ja,jz
      do i = ia,iz
         do k = 1,m1
            vctr2(k) = zt(k) * rtg(i,j) + top(i,j)
         enddo
         CALL htint (nzp,u01dn(1,ngrid),zt,nz,vctr5,vctr2)
         do k = 2,m1-1
            coriolis_contribution2 = fcor(i,j) * vctr5(k)
            vt(k,i,j) = vt(k,i,j) + coriolis_contribution2
            if(iuvwtend>=1) then
              cor_term(k,i,j) = cor_term(k,i,j) + coriolis_contribution2
            endif
         enddo
      enddo
   enddo

else

   do j = ja,jz
      do i = ia,iz
         do k = 2,m1-1
            coriolis_contribution2 = fcor(i,j) * u01dn(k,ngrid)
            vt(k,i,j) = vt(k,i,j) + coriolis_contribution2
            if(iuvwtend>=1) then
              cor_term(k,i,j) = cor_term(k,i,j) + coriolis_contribution2
            endif
         enddo
      enddo
   enddo

endif

! Store accumulated Coriolis term for budget diagnostics
if(iuvwtend>=1) then
  basic_g(ngrid)%vp_coriolis(1:m1,1:m2,1:m3) = cor_term(1:m1,1:m2,1:m3)
  deallocate(cor_term)
endif

return
END SUBROUTINE corlsv

