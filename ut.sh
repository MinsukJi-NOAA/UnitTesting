#!/bin/bash
# Perform unit tests
set -eux

error() {
  echo
  echo "$@" 1>&2
  exit 1
}

usage() {
  set +x
  echo
  echo "Usage: $program -n <test-name> { -c <baseline-cases> | -r <unit-test-cases> } [-h]"
  echo
  echo "  -n  specify <test-name>"
  echo
  echo "  -c  create new baseline results. <baseline-cases> is"
  echo "      either 'all' or any combination of 'std','32bit','debug'"
  echo
  echo "  -r  run unit tests. <unit-test-cases> is either 'all' or any combination"
  echo "      of 'std','thread','mpi','decomp','restart','32bit','debug'"
  echo
  echo "  -h  display this help and exit"
  echo
  echo "  Examples:"
  echo "    -create new baselines:"
  echo "      ut.sh -n fv3_control -c all: std, 32bit, debug for fv3_control"
  echo "      ut.sh -n fv3_iau -c std,debug: std, debug for fv3_iau"
  echo "      ut.sh -n fv3_gfdlmprad_gws -c 32bit: 32bit for fv3_gfdlmprad_gws"
  echo
  echo "    -run unit tests:"
  echo "      ut.sh -n fv3_cpt -r all: std,thread,mpi,decomp,restart,32bit,debug for fv3_cpt"
  echo "      ut.sh -n fv3_control -r thread,decomp: thread,decomp for fv3_control"
  echo "      ut.sh -n fv3_stochy -r restart: restart for fv3_stochy"
  echo
  set -x
}

usage_and_exit() {
  usage
  exit $1
}

readonly program=$(basename $0)
[[ $# -eq 0 ]] && usage_and_exit 1

# make sure only one instance of ut.sh is running
#readonly lockdir=${PATHRT}/lock
#if mkdir $lockdir 2>/dev/null; then
#  echo $(hostname) $$ > ${lockdir}/PID
#else
#  error "Only one instance of ut.sh can be running at a time"
#fi

# PATHRT - Path to unit tests directory
readonly PATHRT=$(cd $(dirname $0) && pwd -P)
cd $PATHRT
# PATHTR - Path to trunk directory
readonly PATHTR=$(cd ${PATHRT}/.. && pwd)
# Default compiler 'intel'
export COMPILER=${NEMS_COMPILER:-intel}
# detect_machine sets ACCNR and MACHINE_ID
source detect_machine.sh
source rt_utils.sh
if [[ $MACHINE_ID = hera.* ]]; then
  export NCEPLIBS=/scratch1/NCEPDEV/global/gwv/l819/lib
  source $PATHTR/NEMS/src/conf/module-setup.sh.inc
  module use $PATHTR/modulefiles/${MACHINE_ID}
  module load fv3

  COMPILER=${NEMS_COMPILER:-intel}
  QUEUE=debug
  dprefix=/scratch1/NCEPDEV
  DISKNM=${dprefix}/nems/emc.nemspara/RT
  STMP=${dprefix}/stmp4
  PTMP=${dprefix}/stmp2
  SCHEDULER=slurm
  #cp fv3_conf/fv3_slurm.IN_hera fv3_conf/fv3_slurm.IN
else
  error "Unknown machine ID. Edit detect_machine.sh file"
fi

mkdir -p ${STMP}/${USER}
NEW_BASELINE=${STMP}/${USER}/FV3_UT/UNIT_TEST
RTPWD=${NEW_BASELINE}
RUNDIR_ROOT=${RUNDIR_ROOT:-${PTMP}/${USER}}/FV3_UT/ut_$$
mkdir -p ${RUNDIR_ROOT}

CREATE_BASELINE=
baseline_cases=
run_unit_test=
unit_test_cases=
TEST_NAME=

while getopts :c:r:n:h opt
do
  case $opt in
    c)
      CREATE_BASELINE=true
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
      echo "CREATE_BASELINE = $CREATE_BASELINE"
      echo "baseline_cases = $baseline_cases"
      echo "run_unit_test = $run_unit_test"
      ;;
    r)
      run_unit_test=true
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
      echo "run_unit_test = $run_unit_test"
      echo "unit_test_cases = $unit_test_cases"
      echo "CREATE_BASELINE = $CREATE_BASELINE"
      ;;
    n)
      TEST_NAME=$OPTARG
      #echo "test-name = $TEST_NAME"
      ;;
    h)
      usage_and_exit 0
      ;;
    '?')
      error "$program: invalid option -$OPTARG"
      ;;
  esac
done

if [ -z $TEST_NAME ]; then
  error "$program: please specify test-name. Try 'ut.sh -h' for usage."
fi

if [[ $CREATE_BASELINE != true && $run_unit_test != true ]]; then
  error "$program: choose either create baselines or run tests. Try 'ut.sh -h' for usage."
elif [[ $CREATE_BASELINE = true && $run_unit_test = true ]]; then
  error "$program: cannot create baselines and run tests at the same time. Try 'ut.sh -h' for usage."
fi

# fill in ut_compile_cases & ut_run_cases
# based on baseline_case & unit_test_cases
ut_compile_cases=
ut_run_cases=
if [[ $CREATE_BASELINE == true ]]; then
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
elif [[ $run_unit_test == true ]]; then
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
echo "ut_compile_cases are $ut_compile_cases"
echo "ut_run_cases are $ut_run_cases"

TESTS_FILE='ut.conf'
[[ -f $TESTS_FILE ]] || error "$TESTS_FILE does not exist"
build_file='ut.bld'
[[ -f $build_file ]] || error "$build_file does not exist"

COMPILE_LOG=${PATHRT}/Compile_$MACHINE_ID.log
REGRESSIONTEST_LOG=${PATHRT}/RegressionTests_$MACHINE_ID.log
LOG_DIR=${PATHRT}/log_$MACHINE_ID
rm -rf ${LOG_DIR}
mkdir ${LOG_DIR}
source default_vars.sh
COMPILE_NR=0
rm -f fail_test
rm -f ../fv3.exe
rm -f fv3_*.x fv3_*.exe modules.fv3_*
# Compile
for i in $ut_compile_cases
do
  # given model and compile_case, select compile option
  while IFS="|" read model comp_case comp_opt
  do
    model=$(echo $model | sed -e 's/^ *//' -e 's/ *$//')
    comp_case=$(echo $comp_case | sed -e 's/^ *//' -e 's/ *$//')
    comp_opt=$(echo $comp_opt | sed -e 's/^ *//' -e 's/ *$//')
    if [[ $model == $TEST_NAME && $comp_case == $i ]]; then
      NEMS_VER=$comp_opt
      break;
    fi
  done < $build_file

  (( COMPILE_NR += 1 ))
  echo "bash compiling for ${model} ${comp_case} with ${NEMS_VER}"
  ./compile.sh $PATHTR/FV3 $MACHINE_ID "${NEMS_VER}" $COMPILE_NR >${LOG_DIR}/compile_${COMPILE_NR}.log 2>&1
  echo "bash compile is done for ${model} ${comp_case}"
done

# Run
for i in $ut_run_cases
do
done

