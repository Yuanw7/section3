!
! License-Identifier: GPL
!
! Copyright (C) 2006 The Yambo Team
!
! Authors (see AUTHORS file for details): CH DS HM
!
integer function a2y(np,pid,lnstr,iinf,iind,iod,icd,ijs,instr,inf,ind,od,com_dir,js)
 !
 use netcdf
 use netcdf_data
 use vec_operate,         ONLY: sort
 use pars,                ONLY: SP,cZERO
 use LOGO,                ONLY: pickup_a_random
 use com,                 ONLY: msg,core_io_path
 use it_m,                ONLY: nrnlvls,rnlvls,rstatus
 use parallel_m,          ONLY: ncpu,myid
 use electrons,           ONLY: levels,E_reset,n_spinor,n_sp_pol
 use D_lattice,           ONLY: n_atoms_species_max
 use pseudo,              ONLY: PP_free,pp_n_l_times_proj_max
 use R_lattice,           ONLY: bz_samp,bz_samp_reset,nkibz
 use wave_func,           ONLY: wf_ncx,io_WF,wf_nb_io_groups,wf_nb_io,wf_igk,wf_nc_k
 use IO_int,              ONLY: io_control,IO_and_Messaging_switch
 use IO_m,                ONLY: OP_WR_CL,NONE,OP_APP_CL,serial_number
 use mod_com2y,           ONLY: interface_presets, force_noWFs
 use mod_wf2y,            ONLY: WF_splitter
 !
 implicit none
 integer,          intent(in) :: lnstr,iind,iod,ijs,np,pid,icd
 integer,          intent(in) :: iinf
 character(lnstr), intent(in) :: instr
 character(iinf),  intent(in) :: inf
 character(iind),  intent(in) :: ind
 character(iod),   intent(in) :: od
 character(ijs),   intent(in) :: js
 character(icd),   intent(in) :: com_dir   
 !
 type(levels)                 :: en
 type(bz_samp)                :: k
 !
 integer                      :: ID,io_err,i_sp_pol,ik,ifrag,ib_grp
 integer,     external        :: io_DB1, io_KB_abinit
 complex(SP), allocatable     :: wf_disk(:,:,:)
 !
 logical, external            :: file_exists
 ! 
 ! Work Space
 !
 integer                     :: ncid, netcdf_error
 !
 ! Presets
 !=========
 a2y   = 0
 ncpu  = np
 myid  = pid
 !
 nrnlvls    =1
 rnlvls(1,1)="a2y"
 rstatus(1) =1
 !
 ! ... Internal Defaults
 !
 call SET_defaults(instr,ind,od,com_dir)
 !
 ! ... C_driver -> YPP information transfer
 !
 call C_driver_transfer()
 !
 call SET_job_strings_and_dirs(js)
 call IO_make_directories("MORE LOG")
 call interface_presets(instr)
 call bz_samp_reset(k)
 call E_reset(en)
#if defined _MEM_CHECK 
 call MEM_defaults( )
 call MEM_treshold_estimate( )
#endif
 !
 ! Switch off report file support & Handle logs
 !
 call IO_and_Messaging_switch("-report +log +fragments_IO_log +timing" )
 !
 ! Report/Log Files
 !
 call INIT_report_and_log_files()
 !
 ! LOGO
 !
 call write_the_logo(6,' ')
 !
 ! S/N
 !======
 serial_number=pickup_a_random(10000._SP)
 !
 ! LOGO
 !
 call msg('s','A(binit) 2 Y(ambo) [NETCDF format]')
 !
 ! Check input filenames 
 !
 call msg('s','Checking input file ...')
 !
 if      (index(trim(inf),'KSS')/=0) then
   NETCDF_kind='KSS'
 else if (index(trim(inf),'WFK')/=0) then
   NETCDF_kind='WFK'
 else
   call msg('ln','File kind not supported! Use either KSS or WFK filename.')
 end if
 !
 call msg('s','NETCDF file ',trim(inf))
 !
 if(.not.file_exists(trim(inf))) then
   call msg('ln','File not found! Specify -F filename.')
   return
 endif
 !
 call msg('s','DBs path set to ',trim(core_io_path))
 !
 ! Open ETSF file for reading
 !
 netcdf_error = nf90_open(path = trim(inf), mode = NF90_NOWRITE, ncid = ncid)
 call netcdf_check(ncid,netcdf_error, 0)
 !
 ! DB1
 !==========================================
 !
 call a2y_db1(en,k,ncid)
 !
 if (force_noWFs) then
   !
   ! Write the data to YAMBO DB1
   !
   call msg('s',' == Writing DB1 ...')
   call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)
   io_err=io_DB1(en,k,ID)
   call msg('ln','done ==')
   return
 endif
 !
 call WF_splitter()
 !
 ! WF & PP
 !==========================================
 !
 if(trim(NETCDF_kind)=='KSS') call msg('s',' == Writing DB2 (wavefunctions) + nlPP ...') 
 !
 if(trim(NETCDF_kind)=='WFK') then
   if ( pp_n_l_times_proj_max == -1) call msg('s',' == Writing DB2 (wavefunctions) ...') 
   if ( pp_n_l_times_proj_max /= -1) call msg('s',' == Writing DB2 (wavefunctions) + nlPP ...') 
 endif
 !
 allocate(wf_disk(wf_ncx,n_spinor,wf_nb_io))
 !
 do i_sp_pol=1,n_sp_pol
   !
   do ik=1,nkibz
     !
     ifrag=ik+(i_sp_pol-1)*nkibz
     !
     wf_disk=cZERO
     !
     do ib_grp=1,wf_nb_io_groups
       !
       ! Read from the etsf-nc file
       !
       call a2y_wf(wf_disk,i_sp_pol,ik,ib_grp,ncid)
       ! 
       ! Write to the YAMBO WF database
       ! 
       if (ifrag==1.and.ib_grp==1) call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2,1/),ID=ID)
       if (ifrag> 1.or. ib_grp> 1) call io_control(ACTION=OP_APP_CL,COM=NONE,SEC=(/ifrag+1,ib_grp/),ID=ID)
       io_err=io_WF(ID,wf_disk)
       !
       if(trim(NETCDF_kind)=='KSS') call a2y_kb_pp(ik,ncid) 
       if( pp_n_l_times_proj_max/=-1 ) then
         if(trim(NETCDF_kind)=='WFK') call a2y_kb_pp_wfk(ik,ncid) 
         if (n_atoms_species_max>0.and.ib_grp==1) then
           if (ifrag==1) call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)
           if (ifrag> 1) call io_control(ACTION=OP_APP_CL,COM=NONE,SEC=(/ifrag+1/),ID=ID)
           io_err=io_KB_abinit(ID) 
         endif
       endif
       !
     enddo
     !
   enddo
   !
 enddo
 !
 deallocate(wf_disk)
 if(trim(NETCDF_kind)=='KSS') call PP_free()
 !
 if(trim(NETCDF_kind)=='WFK') then
   do ik=1,nkibz
     call sort(wf_igk(:wf_nc_k(ik),ik))
   enddo
 endif
 !
 call msg('l','done ==')
 !
 ! Write the data to YAMBO DB1
 !
 call msg('s',' == Writing DB1 ...')
 call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)
 io_err=io_DB1(en,k,ID)
 call msg('ln','done ==')
 !
 ! Close file
 !
 netcdf_error = nf90_close(ncid)
 !
end function
