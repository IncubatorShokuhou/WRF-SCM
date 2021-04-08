#!/bin/csh -x
# sets environment and command-line arguments for the ncl script
# NOTES/TODO: 
# 1.  Need to make the cdl file have the correct number layers - get from met_em* file. 

set ensSize = 0 # ensemble size
set forceCDL = forcing_file_era5.cdl # forcing_file.cdl文件的文件名  .注意这里需要仔细修改，保证层数与era5的met_em文件层数对应
set metPath = /home/nfs/nfsstorage2/ai/lvhao/SCM/WPS # met_em文件所在的目录
#set metPath = /home/nfs/nfsstorage2/ai/lvhao/SCM/WRF_SCM_forcing/met_em/06
set simLength = 2592000 # 整个模拟的时长(单位：秒)   60*86400=5184000
set forcingInterval = -3600 # forcing场的时间间隔。单位：秒。如果这个值是负数，则代表不需要进行插值
# following in C-syle indexing (starts at 0)
set xll = 4; # lower left x index of mass grid square containing SCM
set yll = 4; # lower left y index of mass grid square containing SCM  scm点位于网格点坐标。从0开始
set randSeed1 = 29 # 随机数种子 (not used for ensSize=0)
set randSeed2 = 376201
# set centerDate = "" # valid initialization date or empty
set centerDate = "2016-07-01" # valid initialization date 开始时间
set centerTime = "00:00:00"
#set forceArcDir = ./WRF-SCM-files/$centerDate
set forceArcRoot = /home/nfs/nfsstorage2/ai/lvhao/SCM/WRF_SCM_forcing/WRF-SCM-files   # 生成的forcing文件的保存目录

# END OF USER MODIFICATIONS

# 检查build_scm_forcing.ncl文件是否存在
if ( ! -e build_scm_forcing.ncl ) then
  echo REQUIRES NCL SCRIPT build_scm_forcing.ncl
  exit 1
endif

# 检查forcing_file.cdl文件是否存在
if ( ! -e $forceCDL ) then
  echo REQUIRES CDL FILE $forceCDL
  exit 1
endif

# 如果centerDate变量不为空，则处理所有met_em文件。否则只处理centerDate一天的文件
if ( $centerDate == "" ) then
  set initList = ( `ls ${metPath}/met_em*${centerTime}.nc` )
else
  set initList = ( ${metPath}/met_em.d01.${centerDate}_${centerTime}.nc )
endif

setenv SIMLENGTH $simLength
setenv METPATH $metPath
setenv XLL $xll
setenv YLL $yll
setenv RANDSEEDa $randSeed1
setenv RANDSEEDb $randSeed2
if ( $forcingInterval > 0 ) setenv FORCING_INTERVAL $forcingInterval

# 对所有日期做循环
foreach centerFile ( $initList )

  set centerBase = `basename $centerFile .nc`
  set centerDate = `echo $centerBase | cut -c 12-30`

  setenv CENTER_DATE $centerDate

  # strip out base name of forcing file template
  set fNameRoot = `basename $forceCDL .cdl`

  set forceArcDir = $forceArcRoot/$centerDate
  if ( ! -d forceArcDir ) mkdir -p $forceArcDir

  # if more than 0 perturbations, copy then call ncl script
  @ imember = 1
  while ( $imember <= $ensSize )

    set cmember = $imember
    if ( $imember < 1000 ) set cmember = 0$cmember
    if ( $imember < 100  ) set cmember = 0$cmember
    if ( $imember < 10   ) set cmember = 0$cmember

    set forcingFile = ${fNameRoot}_${cmember}.nc     # 生成的nc文件的名字
    ncgen -o $forcingFile $forceCDL

    # 调用ncl脚本
    setenv FORCE_FILE_NAME $forcingFile
    setenv ENSEMBLE_MEMBER $imember
    ncl -x < build_scm_forcing.ncl

    if ( $status ) then
      echo FAILED on ensemble member $imember
      exit 1
    endif

    # time interpolate if needed
    if ( $forcingInterval > 0 ) then
      ncl -x < time_interpolate_forcing.ncl
      /bin/mv -f forcing_temp.nc $forcingFile
    endif
  
    if ( $status ) then
      echo FAILED on time interpolation for ensemble member $imember
      exit 1
    endif

    # rename and concatenate some of the output
    cat surface_init.txt > $forceArcDir/input_sounding_${cmember}
    cat profile_init.txt >> $forceArcDir/input_sounding_${cmember}
    /bin/cp -f soil_init.txt $forceArcDir/input_soil_${cmember}
    /bin/mv -f $forcingFile $forceArcDir

    @ imember ++
  end

  # finally, create the unperturbed one
  set forcingFile = ${fNameRoot}.nc
  ncgen -o $forcingFile $forceCDL

  setenv FORCE_FILE_NAME $forcingFile
  setenv ENSEMBLE_MEMBER 0

  ncl -x < build_scm_forcing.ncl

  if ( $status ) then
    echo FAILED on control
    exit 1
  endif

  # time interpolate if needed
  if ( $forcingInterval > 0 ) then
    ncl -x < time_interpolate_forcing.ncl
    /bin/mv -f forcing_temp.nc $forcingFile
  endif

  if ( $status ) then
    echo FAILED on time interpolation for control
    exit 1
  endif

 
  # rename and concatenate some of the output
  cat surface_init.txt > $forceArcDir/input_sounding
  cat profile_init.txt >> $forceArcDir/input_sounding
  /bin/cp -f soil_init.txt $forceArcDir/input_soil
  /bin/mv -f $forcingFile $forceArcDir
  /bin/mv -f suggested_namelist.txt $forceArcDir
end # big loop through init dates

echo SUCCESS
exit 0


