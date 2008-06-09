c-----------------------------------------------------------------------
      subroutine mapelpr()
      include 'SIZE'
      include 'INPUT'
      include 'PARALLEL'
      include 'SCRCT'
      include 'SOLN'
      include 'TSTEP'
c
      logical ifverbm
c
      MFIELD=2
      IF (IFFLOW) MFIELD=1
      IF (IFMVBD) MFIELD=0
c
c     Set up TEMPORARY value for NFIELD - NFLDT
c
      NFLDT = 1
      IF (IFHEAT) NFLDT = 2 + NPSCAL
c
c     Distributed memory processor mapping
c
      IF (NP.GT.NELGV) THEN
         WRITE(6,1000) NP,NELGV
 1000    FORMAT(2X,'ERROR: Too many processors (',I3
     $        ,') for to few elements (',I3,').'
     $        ,/,2X,'ABORTING IN MAPELPR.')
         call exitt
      ENDIF
c
      call set_proc_map()
c
c     Update the number of elements on each processor.
c
      LL1P=(LDIMT1+1)*LP
      CALL IZERO (NELP,LL1P)
      NL1P=(LDIMT1+1)*NP
      DO 1200 IFIELD=MFIELD,NFLDT
         IF (IFTMSH(IFIELD)) THEN
            NELP(IFIELD,NODE) = NELT
            NELG(IFIELD)      = NELGT
         ELSE
            NELP(IFIELD,NODE) = NELV
            NELG(IFIELD)      = NELGV
         ENDIF
 1200 CONTINUE
c
c     since lelg = lp * lelt 
c     this works when lelt >= ldimt1+1
c
      if (np.gt.1.and.NL1P.gt.LELG) then
         if (nid.eq.0) then
            write(6,*) 'ERROR MAPELPR (map2.f) :: insuf. work',LELG,NL1P
            write(6,*) 'increase LELG in SIZEu to ',NL1P
         endif
         CALL IGOP (NELP,LELGWORK,'+  ',1)
         call flush_io
         call exitt
      endif
      CALL IGOP (NELP,LELGWORK,'+  ',NL1P)
C
C     Output the processor-element map:
C
C     IF (NP.GT.1.AND.IPASS.EQ.2.AND.NID.EQ.0) THEN
C     IF (NP.GT.0.AND.IPASS.EQ.2.AND.NID.EQ.0) THEN
C
C
      ifverbm=.true.
      if (np.gt.2050) ifverbm=.false.
      if (nid.eq.0.and.ifverbm) then
         IFLD=1
         IF (IFHEAT) IFLD=2
         DO 1300 IP=1,NP
            n8=min(8,nelp(ifld,ip))
            WRITE(6 ,1310) IP,(LGLEL(IE,IP),IE=1,N8)
            IF (NELP(ifld,ip).gt.8)
     $       WRITE(6 ,1315) (LGLEL(IE,IP),IE=9,NELP(IFLD,IP))
 1300    CONTINUE
 1310    FORMAT('IP',I6,' IEG',8I8)
 1315    FORMAT('  ',6X,'    ',8I8)
      endif
c
c
C
C     Check elemental distribution
C
C      IF (IPASS.EQ.2.AND.PARAM(156).eq.9) THEN
C         NXYZ=NX1*NY1*NZ1
C         DO 1400 IE=1,NELT
C            VTMP1=NODE
c            VTMP2=IE
C            CALL CFILL(VX(1,1,1,IE) ,VTMP1,NXYZ)
C            CALL CFILL(VY(1,1,1,IE) ,VTMP2,NXYZ)
C            CALL CFILL(T(1,1,1,IE,1),VTMP1,NXYZ)
C 1400    CONTINUE
C         call prepost(.true.,'   ')
C      ENDIF
C
      return
      end
c-----------------------------------------------------------------------
      subroutine set_proc_map()
C
C     Compute element to processor distribution according to (weighted) 
C     physical distribution in an attempt to minimize exposed number of
C     element interfaces.
C
      include 'SIZE'
      include 'INPUT'
      include 'PARALLEL'
      include 'SOLN'
      include 'SCRCT'
      include 'TSTEP'
      include 'ZPER'
c
      REAL*8 dnekclock,t0
c
      t0 = dnekclock()
c     if (.not.(ifgtp.or.ifgfdm)) then
      if (.not.ifgtp) then
c
c        rsb element to processor mapping 
c
         inc = 2**ndim 
         call get_map(gllnid,nelgv,inc)
      endif

      if (ifzper.or.ifgfdm.or.ifgtp) then ! special processor map
         call gfdm_elm_to_proc(gllnid,np)
      endif

      if (nid.eq.0) write(6,*) 'nelgt:',nelgt,nelgv
      if (nid.eq.0) write(6,*) 'nelt:',nelt,nelv

      if (nelgt.gt.nelgv) then ! distribute additional solid elements
         call solid_element_map(gllnid,nelgv,nelgt)
      endif
c
c     compute global to local map (no processor info)
c
      IEL=0
      CALL IZERO(GLLEL,NELGT)
      DO IEG=1,NELGT
         IF (GLLNID(IEG).EQ.NID) THEN
            IEL = IEL + 1
            GLLEL(IEG)=IEL
            NELT = IEL
            if (ieg.le.nelgv) NELV = IEL
         ENDIF
c        write(6,*) 'map2 ieg:',ieg,nelv,nelt,nelgv,nelgt
      ENDDO
c
c     dist. global to local map to all processors
c
      CALL IGOP (GLLEL ,LELGWORK,'+  ',NELGT)
c
c     compute local to global map
c     (i.e. returns global element number given local index and proc id)
c
      DO IEG=1,NELGT
         NODE1=GLLNID(IEG)+1
         IE   =GLLEL (IEG)
         LGLEL(IE,NODE1)=IEG
      ENDDO
c
c     All Done.
c
      return
      end
c-----------------------------------------------------------------------
      subroutine gfdm_elm_to_proc(gllnid,np)
c
c
      include 'SIZE'
      include 'ZPER'
c
      integer gllnid(lelg)
c
      common /ctmp1/ map_st(lelg)
      common /ctmp0/ iwork(0:lp)
      integer nelbox(3),nstride_box(3)
c
      call gfdm_set_pst(ip,is,it,nelbox,nstride_box,nx2,ny2,nz2)
c
      nep = nelbox(ip)
      nes = nelbox(is)
      net = nelbox(it)
c
      nst = nes*net
      if (nst.lt.np) then
         if (nid.eq.0) 
     $   write(6,*) 'ERROR, number of elements in plane must be > np'
     $   ,nst,np,nep,nes,net
         call exitt
      endif
c
c
      call gfdm_map_2d(map_st,nes,net,iwork,np)
      call gfdm_build_global_el_map (gllnid,map_st,nes,net
     $                                     ,nelbox,nstride_box,ip,is,it)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine gfdm_map_2d(map_st,nes,net,num_el,np)
c
c     Set up a 2D processor decomposition of an NES x NET array.
c
      integer map_st(nes,net),num_el(0:np)
c
c     First a stupid dealing algorithm to determine how many
c     elements on each processor

      do i=0,np
         num_el(i) = 0
      enddo
c
      k = np-1
      do i=1,nes*net
         num_el(k) = num_el(k)+1
         k=k-1
         if (k.lt.0) k = np-1
      enddo
c
      jnid = 0
      nel_cnt = 0
      nel_cur = num_el(jnid)
      do j=1,net,2
         do i=1,nes                 ! Count down
            nel_cnt = nel_cnt + 1
            if (nel_cnt.gt.nel_cur) then
               jnid=jnid+1
               nel_cur = num_el(jnid)
               nel_cnt = 1
            endif
            map_st(i,j) = jnid
         enddo
c
         j1 = j+1
         if (j1.le.net) then
            do i=nes,1,-1                ! Count up
               nel_cnt = nel_cnt + 1
               if (nel_cnt.gt.nel_cur) then
                  jnid=jnid+1
                  nel_cur = num_el(jnid)
                  nel_cnt = 1
               endif
               map_st(i,j1) = jnid
            enddo
         endif
      enddo
c
      return
      end
c-----------------------------------------------------------------------
      subroutine gfdm_set_pst(ip,is,it,nelbox,nstride_box,nxp,nyp,nzp)
c
      include 'SIZE'
      include 'INPUT'
      include 'ZPER'
c
      integer nelbox(3),nstride_box(3)
c
      if (if3d) then
         if (param(118).lt.0) then
            ip = 3
            is = 1
            it = 2
         elseif (param(117).lt.0) then
            ip = 2
            is = 3
            it = 1
         else
            ip = 1
            is = 2
            it = 3
         endif
      else
         if (param(117).lt.0) then
            ip = 2
            is = 1
            it = 3
         else
            ip = 1
            is = 2
            it = 3
         endif
      endif
c
      pst2lex(1)=ip       ! identify x-, y- or z with primary direction
      pst2lex(2)=is
      pst2lex(3)=it
c
      lex2pst(ip)=1
      lex2pst(is)=2
      lex2pst(it)=3
c
      nelbox(1) = nelx
      nelbox(2) = nely
      nelbox(3) = nelz
c
      nstride_box(1) = 1
      nstride_box(2) = nelx
      nstride_box(3) = nelx*nely
c
      ngfdm_p(1) = nelx*nxp
      ngfdm_p(2) = nely*nyp
      ngfdm_p(3) = nelz*nzp
      write(6,*) 'ngfdm:',(ngfdm_p(k),k=1,3)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine gfdm_build_global_el_map (gllnid,map_st,nes,net
     $                                     ,nelbox,nstride_box,ip,is,it)
c
      include 'SIZE'
      integer gllnid(1)
      integer map_st(nes,net)
      integer nelbox(3),nstride_box(3)
c
      integer proc
c
      do jt=1,nelbox(it)
      do js=1,nelbox(is)
         proc = map_st(js,jt)
         do jp=1,nelbox(ip)
            ieg = 1 + nstride_box(ip)*(jp-1)  ! nstride_p=nes*net
     $              + nstride_box(is)*(js-1)
     $              + nstride_box(it)*(jt-1)
            gllnid(ieg) = proc
         enddo
      enddo
      enddo
c
      return
      end
c-----------------------------------------------------------------------
      subroutine outmati(u,m,n,name6)
      integer u(m,n)
      character*6 name6
      common /nekmpi/ nid,np,nekcomm,nekgroup,nekreal
c
c     Print out copies of a global matrix
c
      write(6,1) nid,m,n,name6
   1  format(//,3i6,'  Matrix:',2x,a6,/)
      do i=1,m
         write(6,2) nid,name6,(u(i,j),j=1,n)
      enddo
   2  format(i3,1x,a6,15i6)
      return
      end
c-----------------------------------------------------------------------
      subroutine solid_element_map
      include 'SIZE'
      include 'PARALLEL'
c
c     num_el_min = ivlmin(glln
c
      return   ! Serial code, for now.
      end
c-----------------------------------------------------------------------
      subroutine get_map
      include 'SIZE'
      include 'TOTAL'

      call f77_get_vert

      return
      end
c-----------------------------------------------------------------------