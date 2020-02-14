#!/bin/bash
set -eux
SECONDS=0
hostname

error() {
  echo
  echo "$@" 1>&2
  exit 1
}

usage() {
  set +x
  echo
  echo "Usage: $program -n <test-name> [ -c <baseline-cases> | -r <unit-test-cases> ] [-k] [-h]"
  echo
  echo "  -n  specify <test-name>"
  echo
  echo "  -c  create new baseline results. <baseline-cases> is"
  echo "      either 'all' or any combination of 'std','32bit','debug'"
  echo
  echo "  -r  run unit tests. <unit-test-cases> is either 'all' or any combination"
  echo "      of 'std','thread','mpi','decomp','restart','32bit','debug'"
  echo
  echo "  -k  keep run directory"
  echo
  echo "  -h  display this help and exit"
  echo
  echo "  Examples"
  echo
  echo "    To create new baselines and run unit tests:"
  echo "      'utest -n fv3_thompson' creates and runs all for fv3_thompson"
  echo
  echo "    To create new baselines only:"
  echo "      'utest -n fv3_control -c all' creates std, 32bit, debug for fv3_control"
  echo "      'utest -n fv3_iau -c std,debug' creates std, debug for fv3_iau"
  echo "      'utest -n fv3_gfdlmprad_gws -c 32bit' creates 32bit for fv3_gfdlmprad_gws"
  echo
  echo "    To run unit tests only:"
  echo "      'utest -n fv3_cpt -r all' runs std,thread,mpi,decomp,restart,32bit,debug for fv3_cpt"
  echo "      'utest -n fv3_control -r thread,decomp' runs thread,decomp for fv3_control"
  echo "      'utest -n fv3_stochy -r restart' runs restart for fv3_stochy"
  echo
  set -x
}

usage_and_exit() {
  usage
  exit $1
}

cleanup() {
  rm -rf ${lockdir}
  trap 0
  exit
}

run_utests() {
  for rc in $ut_run_cases; do
    # Load namelist default and override values
    source default_vars.sh
    source ${PATHRT}/tests/$TEST_NAME
    export RUN_SCRIPT

    comp_nm=std
    case $rc in
      std)
        RESTART_INTERVAL=12
        ;;
      thread)
        THRD=2
        # INPES is sometimes odd, so use JNPES. Make sure JNPES is divisible by THRD
        JNPES=$(( JNPES/THRD ))
        TASKS=$(( INPES*JNPES*6 + WRITE_GROUP*WRTTASK_PER_GROUP ))
        TPN=$(( TPN/THRD ))
        NODES=$(( TASKS/TPN + 1 ))
        ;;
      mpi)
        JNPES=$(( JNPES/2 ))
        TASKS=$(( INPES*JNPES*6 + WRITE_GROUP*WRTTASK_PER_GROUP ))
        NODES=$(( TASKS/TPN + 1 ))
        ;;
      decomp)
        temp=$INPES
        INPES=$JNPES
        JNPES=$temp
        ;;
      restart)
        # These parameters are different for regional restart, and won't work
        WARM_START=.T.
        NGGPS_IC=.F.
        EXTERNAL_IC=.F.
        MAKE_NH=.F.
        MOUNTAIN=.T.
        NA_INIT=0
        NSTF_NAME=2,0,1,0,5

        LIST_FILES="phyf024.tile1.nc phyf024.tile2.nc phyf024.tile3.nc phyf024.tile4.nc \
                    phyf024.tile5.nc phyf024.tile6.nc dynf024.tile1.nc dynf024.tile2.nc \
                    dynf024.tile3.nc dynf024.tile4.nc dynf024.tile5.nc dynf024.tile6.nc \
                    RESTART/coupler.res RESTART/fv_core.res.nc RESTART/fv_core.res.tile1.nc \
                    RESTART/fv_core.res.tile2.nc RESTART/fv_core.res.tile3.nc
                    RESTART/fv_core.res.tile4.nc RESTART/fv_core.res.tile5.nc \
                    RESTART/fv_core.res.tile6.nc RESTART/fv_srf_wnd.res.tile1.nc \
                    RESTART/fv_srf_wnd.res.tile2.nc RESTART/fv_srf_wnd.res.tile3.nc \
                    RESTART/fv_srf_wnd.res.tile4.nc RESTART/fv_srf_wnd.res.tile5.nc \
                    RESTART/fv_srf_wnd.res.tile6.nc RESTART/fv_tracer.res.tile1.nc \
                    RESTART/fv_tracer.res.tile2.nc RESTART/fv_tracer.res.tile3.nc \
                    RESTART/fv_tracer.res.tile4.nc RESTART/fv_tracer.res.tile5.nc \
                    RESTART/fv_tracer.res.tile6.nc RESTART/phy_data.tile1.nc \
                    RESTART/phy_data.tile2.nc RESTART/phy_data.tile3.nc RESTART/phy_data.tile4.nc \
                    RESTART/phy_data.tile5.nc RESTART/phy_data.tile6.nc RESTART/sfc_data.tile1.nc \
                    RESTART/sfc_data.tile2.nc RESTART/sfc_data.tile3.nc RESTART/sfc_data.tile4.nc \
                    RESTART/sfc_data.tile5.nc RESTART/sfc_data.tile6.nc"
        #LIST_FILES="phyf024.nemsio dynf024.nemsio \
        ;;
      32bit)
        comp_nm=$rc
        ;;
      debug)
        comp_nm=$rc
        ;;
    esac

    echo "case: $rc; THRD: $THRD; INPES: $INPES; JNPES: $JNPES; TASKS: $TASKS; TPN: $TPN; NODES: $NODES"

    RT_SUFFIX="_$rc"
    BL_SUFFIX="_$comp_nm"

    cat <<- EOF > ${RUNDIR_ROOT}/run_test_$rc.env
		export MACHINE_ID=${MACHINE_ID}
		export RTPWD=${RTPWD}
		export PATHRT=${PATHRT}
		export PATHTR=${PATHTR}
		export NEW_BASELINE=${NEW_BASELINE}
		export CREATE_BASELINE=${CREATE_BASELINE}
		export RT_SUFFIX=${RT_SUFFIX}
		export BL_SUFFIX=${BL_SUFFIX}
		export SCHEDULER=${SCHEDULER}
		export ACCNR=${ACCNR}
		export QUEUE=${QUEUE}
		export ROCOTO=${ROCOTO}
		export LOG_DIR=${LOG_DIR}
		EOF

    ./run_test.sh $PATHRT $RUNDIR_ROOT $TEST_NAME $rc $comp_nm > $LOG_DIR/run_${TEST_NAME}_$rc.log 2>&1
  done
}

trap 'echo utest interrupted; cleanup' INT
trap 'echo utest quit; cleanup' QUIT
trap 'echo utest terminated; cleanup' TERM
trap 'echo utest error on line $LINENO; cleanup' ERR
trap 'echo utest finished; cleanup' EXIT

########################################################################
####                       PROGRAM STARTS                           ####
########################################################################
readonly program=$(basename $0)
[[ $# -eq 0 ]] && usage_and_exit 1

# Default compiler: intel
export COMPILER=${NEMS_COMPILER:-intel}
# detect_machine sets ACCNR and MACHINE_ID
source detect_machine.sh
# PATHRT - Path to unit tests directory
readonly PATHRT=$(cd $(dirname $0) && pwd -P)
cd $PATHRT
# PATHTR - Path to trunk directory
readonly PATHTR=$(cd ${PATHRT}/.. && pwd)

# make sure only one instance of utest is running
readonly lockdir=${PATHRT}/lock
if mkdir $lockdir 2>/dev/null; then
  echo $(hostname) $$ > ${lockdir}/PID
else
  error "Only one instance of utest can be running at a time"
fi

# Log directory
LOG_DIR=${PATHRT}/log_ut_$MACHINE_ID
rm -rf ${LOG_DIR}
mkdir ${LOG_DIR}
# ROCOTO, ECFLOW not used, but defined for compatibility with rt_fv3.sh
ROCOTO=false
ECFLOW=false

# Machine-dependent libraries, modules, variables, etc.
if [[ $MACHINE_ID = hera.* ]]; then
  export NCEPLIBS=/scratch1/NCEPDEV/global/gwv/l819/lib
  source $PATHTR/NEMS/src/conf/module-setup.sh.inc
  module use $PATHTR/modulefiles/${MACHINE_ID}
  module load fv3

  COMPILER=${NEMS_COMPILER:-intel} # in case compiler gets deleted by module purge
  QUEUE=debug
  dprefix=/scratch1/NCEPDEV
  DISKNM=$dprefix/nems/emc.nemspara/RT
  STMP=${dprefix}/stmp4
  PTMP=${dprefix}/stmp2
  SCHEDULER=slurm
  cp fv3_conf/fv3_slurm.IN_hera fv3_conf/fv3_slurm.IN
else
  error "Unknown machine ID. Edit detect_machine.sh file"
fi

CREATE_BASELINE=true
baseline_cases=
run_unit_test=true
unit_test_cases=
TEST_NAME=
keep_rundir=false

# Parse command line arguments
while getopts :c:r:n:kh opt; do
  case $opt in
    c)
      run_unit_test=false
      if [ $OPTARG = all ]; then
        baseline_cases=std,32bit,debug
      else
        baseline_cases=$OPTARG
      fi
      baseline_cases=$(echo $baseline_cases | sed -e 's/^ *//' -e 's/ *$//' -e 's/,/ /g')
      for i in $baseline_cases
      do
        if [[ $i != std && $i != 32bit && $i != debug ]]; then
          error "Invalid baseline_cases specified: $i"
        fi
      done
      ;;
    r)
      CREATE_BASELINE=false
      if [ $OPTARG = all ]; then
        unit_test_cases=std,thread,mpi,decomp,restart,32bit,debug
      else
        unit_test_cases=$OPTARG
      fi
      unit_test_cases=$(echo $unit_test_cases | sed -e 's/^ *//' -e 's/ *$//' -e 's/,/ /g')
      for i in $unit_test_cases
      do
        if [[ $i != std && $i != thread && $i != mpi && $i != decomp && \
              $i != restart && $i != 32bit && $i != debug ]]; then
          error "Invalid unit_test_cases specified: $i"
        fi
      done
      ;;
    n)
      TEST_NAME=$OPTARG
      #echo "test-name = $TEST_NAME"
      ;;
    k)
      keep_rundir=true
      ;;
    h)
      usage_and_exit 0
      ;;
    '?')
      error "$program: invalid option -$OPTARG"
      ;;
  esac
done

# TEST_NAME is a required argument
if [ -z $TEST_NAME ]; then
  error "$program: please specify test-name. Try 'utest -h' for usage."
fi

# Default where neither -c nor -r is specified: compile and run all cases
if [[ $CREATE_BASELINE == true && run_unit_test == true ]]; then
  baseline_cases=std,32bit,debug
  unit_test_cases=std,thread,mpi,decomp,restart,32bit,debug
fi

echo "baseline_cases = $baseline_cases"
echo "unit_test_cases = $unit_test_cases"

# Fill in ut_compile_cases & ut_run_cases based on baseline_cases & unit_test_cases
# Cases are sorted in the order: std,thread,mpi,decomp,restart,32bit,debug
ut_compile_cases=
ut_run_cases=
if [[ $CREATE_BASELINE == true && $run_unit_test == true ]]; then
  ut_compile_cases="1std 232bit 3debug"
  ut_run_cases="1std 2thread 3mpi 4decomp 5restart 632bit 7debug"
elif [[ $CREATE_BASELINE == true && $run_unit_test == false ]]; then
  for i in $baseline_cases; do
    case $i in
      std)
        ut_compile_cases+=" 1$i"
        ut_run_cases+=" 1$i"
        ;;
      32bit)
        ut_compile_cases+=" 2$i"
        ut_run_cases+=" 2$i"
        ;;
      debug)
        ut_compile_cases+=" 3$i"
        ut_run_cases+=" 3$i"
        ;;
    esac
  done
elif [[ $run_unit_test == true && $CREATE_BASELINE == false ]]; then
  for i in $unit_test_cases; do
    case $i in
      std)
        ut_compile_cases+=" 1$i"
        ut_run_cases+=" 1$i"
        ;;
      thread)
        ut_compile_cases+=" 1std"
        ut_run_cases+=" 2$i"
        ;;
      mpi)
        ut_compile_cases+=" 1std"
        ut_run_cases+=" 3$i"
        ;;
      decomp)
        ut_compile_cases+=" 1std"
        ut_run_cases+=" 4$i"
        ;;
      restart)
        ut_compile_cases+=" 1std"
        ut_run_cases+=" 5$i"
        ;;
      32bit)
        ut_compile_cases+=" 2$i"
        ut_run_cases+=" 6$i"
        ;;
      debug)
        ut_compile_cases+=" 3$i"
        ut_run_cases+=" 7$i"
        ;;
    esac
  done
fi
ut_compile_cases=$(echo $ut_compile_cases | tr " " "\n" | sort -u)
ut_compile_cases=$(echo $ut_compile_cases | sed -e 's/^[0-9]//g' -e 's/ [0-9]/ /g')
ut_run_cases=$(echo $ut_run_cases | tr " " "\n" | sort -u)
ut_run_cases=$(echo $ut_run_cases | sed -e 's/^[0-9]//g' -e 's/ [0-9]/ /g')
if [[ ! $ut_run_cases =~ ^std && $ut_run_cases =~ restart ]]; then
  ut_run_cases="std ${ut_run_cases}"
fi
echo "ut_compile_cases are $ut_compile_cases"
echo "ut_run_cases are $ut_run_cases"

########################################################################
####                            COMPILE                             ####
########################################################################
# build_file specifies compilation options
build_file='utest.bld'
[[ -f ${build_file} ]] || error "${build_file} does not exist"

compile_log=${PATHRT}/Compile_ut_$MACHINE_ID.log
rm -f fv3_*.exe modules.fv3_* ${compile_log}

while IFS="|" read model comp_opt; do
  model_found=false
  model=$(echo $model | sed -e 's/^ *//' -e 's/ *$//')
  comp_opt=$(echo $comp_opt | sed -e 's/^ *//' -e 's/ *$//')
  if [[ $model == ${TEST_NAME} ]]; then
    base_opt=${comp_opt}
    model_found=true
    break
  fi
done < ${build_file}
if [[ ${model_found} == false ]]; then
  error "Build options for $TEST_NAME not found. Please edit utest.bld."
fi

for name in $ut_compile_cases; do
  NEMS_VER=${base_opt}
  case $name in
    std)
      # Nothing to be done
      ;;
    32bit)
      if [[ ${base_opt} =~ "32BIT=Y" ]]; then
        NEMS_VER=$(echo ${base_opt} | sed -e 's/32BIT=Y/32BIT=N/')
      elif [[ ${base_opt} =~ "32BIT=N" ]]; then
        NEMS_VER=$(echo ${base_opt} | sed -e 's/32BIT=N/32BIT=Y/')
      else
        NEMS_VER="${base_opt} 32BIT=Y"
      fi
      ;;
    debug)
      NEMS_VER="${base_opt} DEBUG=Y"
      ;;
  esac

  echo "compile case: $name"
  echo "NEMS_VER: $NEMS_VER"

  ./compile.sh $PATHTR/FV3 $MACHINE_ID "${NEMS_VER}" $name >${LOG_DIR}/compile_${TEST_NAME}_$name.log 2>&1
  echo "bash compile is done for ${model} ${comp_case} with ${NEMS_VER}"
done

########################################################################
####                              RUN                               ####
########################################################################
mkdir -p ${STMP}/${USER}
NEW_BASELINE=${STMP}/${USER}/FV3_UT/UNIT_TEST
RTPWD=$DISKNM/NEMSfv3gfs/develop-20191230
if [[ $CREATE_BASELINE == true ]]; then
  rm -rf $NEW_BASELINE
  mkdir -p $NEW_BASELINE  

  rsync -a "${RTPWD}"/FV3_* "${NEW_BASELINE}"/
  rsync -a "${RTPWD}"/WW3_* "${NEW_BASELINE}"/
fi

# Directory where all simulations are run
RUNDIR_ROOT=${RUNDIR_ROOT:-${PTMP}/${USER}}/FV3_UT/ut_$$
mkdir -p ${RUNDIR_ROOT}
# unittest_log is different from REGRESSIONTEST_LOG
# defined in run_test.sh and passed onto rt_utils.sh
unittest_log=${PATHRT}/UnitTests_$MACHINE_ID.log
rm -f fail_test ${unittest_log}

if [[ $CREATE_BASELINE == true && $run_unit_test == true ]]; then
  # Run to create baseline
  ut_run_cases='std 32bit debug'
  run_utests
  rm -rf ${RUNDIR_ROOT}/*
  rm -f ${LOG_DIR}/run_* ${LOG_DIR}/rt_*
  # Run to compare with baseline
  ut_run_cases='std thread mpi decomp restart 32bit debug'
  CREATE_BASELINE=false
  RTPWD=${NEW_BASELINE}
  run_utests
elif [[ $CREATE_BASELINE == true && $run_unit_test == false ]]; then
  # Run to create baselind
  run_utests
elif [[ $CREATE_BASELINE == false && $run_unit_test == true ]]; then
  # Run to compare with baseline
  if [[ ! -d $NEW_BASELINE ]]; then
    error "There is no baseline to run unit tests against. Create baselines first."
  fi
  RTPWD=${NEW_BASELINE}
  run_utests
fi

########################################################################
####                       UNIT TEST STATUS                         ####
########################################################################
set +e
cat ${LOG_DIR}/compile_*.log > ${compile_log}
cat ${LOG_DIR}/rt_*.log >> ${unittest_log}

if [[ -e fail_test ]]; then
  echo "FAILED TESTS: " | tee -a ${unittest_log}
  while read -r failed_test_name
  do
    echo "Test ${failed_test_name} failed " | tee -a ${unittest_log}
  done < fail_test
  echo "UNIT TEST FAILED" | tee -a ${unittest_log}
else
  echo "UNIT TEST WAS SUCCESSFUL" | tee -a ${unittest_log}

  rm -f fv3_*.x fv3_*.exe modules.fv3_*
  [[ ${keep_rundir} == false ]] && rm -rf ${RUNDIR_ROOT}
fi

date >> ${unittest_log}
elapsed_time=$(printf '%02dh:%02dm:%02ds\n' $(($SECONDS%86400/3600)) $(($SECONDS%3600/60)) $(($SECONDS%60)))
echo "Elapsed time: ${elapsed_time}. Have a nice day!" || tee -a ${unittest_log}
