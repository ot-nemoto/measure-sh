#!/bin/bash

function usage() {
cat << EOF
Usage:

  ${0} [-o directory] [-i interval] [-t term] [-h] [-v]

    -o <arg> : Specify results directory
               Default : '\$(cd \$(dirname \$0);pwd)/result-\`date +%Y%m%d%H%M%S\`'
                 For example, '$(cd $(dirname $0);pwd)/result-`date +%Y%m%d%H%M%S`'
    -i <arg> : Specify interval (range 1 .. 60)
               Default : 1
    -t <arg> : Specify measure term
    -v       : Verbose
    -h       : Get help

EOF
exit 0
}

UTIL_DIR=$(cd $(dirname $0);pwd)
RESULT_DIR=./result-`date +%Y%m%d%H%M%S`
INTERVAL=1

while getopts "o:i:t:hv" OPT; do
  case ${OPT} in
    o) RESULT_DIR="${OPTARG}";;
    i) INTERVAL="${OPTARG}";;
    t) MEASURE_TERM="${OPTARG}";;
    v) VERBOSE=1;;
    h|:|\?) usage;;
  esac
done

shift $(( $OPTIND - 1 ))

### Validateion
test `expr "${INTERVAL}" : '[0-9]*$'` -eq 0 && usage
test ${INTERVAL} -lt 1  && usage
test ${INTERVAL} -gt 60 && usage
test "${MEASURE_TERM}" && test `expr "${MEASURE_TERM}" : '[0-9]*$'` -eq 0 && usage

test ! -d ${RESULT_DIR} && mkdir -p ${RESULT_DIR}

### CPU LIST
LIST_CPU=(`cat /proc/cpuinfo | \
  grep ^processor | \
  awk -v FS=: ' \
    {
      sub (/[ \t]+$/, "", $2);
      sub (/^[ \t]+/, "", $2);
      print $2
    }
  '`)

### INTERFACE LIST
LIST_IF=(`ls /proc/sys/net/ipv4/conf/ | \
  grep -v all | \
  grep -v default`)

### DEVICE LIST
S_NR=`expr \`iostat -xd | grep -n ^Device: | cut -d: -f1\` + 1`
E_NR=`iostat -xd  | wc -l`
LIST_DEV=(`iostat -xd | \
  awk -v FS=" " -v S=${S_NR} -v E=${E_NR} ' \
    NR==S,NR==E {
      print $1
    }' | \
  grep -v '^$'`)

### MOUNTED LIST
LIST_MNT=(`mount | awk '{print $3}'`)

### VARBOSE
S_TIME=`date '+%s'`
test ${VERBOSE} && cat <<EOF
Results directory : ${RESULT_DIR}
Measure interval  : ${INTERVAL} sec

Processors        : ${LIST_CPU[@]}
Interfaces        : ${LIST_IF[@]}
IO-devices        : ${LIST_DEV[@]}
Mounted           : ${LIST_MNT[@]}

Start time        : `date -d "1970/01/01 UTC ${S_TIME} sec"`
EOF

sh ${UTIL_DIR}/create_chart.sh -o ${RESULT_DIR} \
  -c "${LIST_CPU[*]}" \
  -i "${LIST_IF[*]}" \
  -d "${LIST_DEV[*]}" \
  -m "${LIST_MNT[*]}"

while :
do
  sleep ${INTERVAL}
  time=`date "+%Y-%m-%d %H:%M:%S"`

  E_TIME=`date '+%s'`
  ELAPSED=$((${E_TIME} - ${S_TIME}))

  test ${MEASURE_TERM} && \
    test ${ELAPSED} -gt ${MEASURE_TERM} && \
    echo "" && \
    exit 0

  ### VARBOSE
  test ${VERBOSE} && \
    NOW=`date -d "1970/01/01 UTC ${E_TIME} sec"` && \
    echo -ne "\rElapsed time      : ${NOW} (${ELAPSED} sec)"

  ### MEMORY
  sh ${UTIL_DIR}/measure_memory.sh -d, -t "$time" >> ${RESULT_DIR}/memory.csv &

  ### CPU
  sh ${UTIL_DIR}/measure_cpu.sh -d, -t "$time" >> ${RESULT_DIR}/cpu.all.csv &
  for c in ${LIST_CPU[@]}
  do
    sh ${UTIL_DIR}/measure_cpu.sh -c ${c} -d, -t "$time" >> ${RESULT_DIR}/cpu.${c}.csv &
  done

  ### LOAD_AVERAGE
  sh ${UTIL_DIR}/measure_loadavg.sh -d, -t "$time" >> ${RESULT_DIR}/loadavg.csv &

  ### NETWORK
  for i in ${LIST_IF[@]}
  do
    sh ${UTIL_DIR}/measure_network.sh -i ${i} -d, -t "$time" >> ${RESULT_DIR}/network.${i}.csv &
  done

  ### DISK_IO
  for i in ${LIST_DEV[@]}
  do
    sh ${UTIL_DIR}/measure_diskio.sh -d, -t "$time" ${i} >> ${RESULT_DIR}/diskio.${i//\//_S_}.csv &
  done

  ### DISK_USE
  for i in ${LIST_MNT[@]}
  do
    sh ${UTIL_DIR}/measure_diskuse.sh -d, -t "$time" ${i} >> ${RESULT_DIR}/diskuse.${i//\//_S_}.csv &
  done
done

exit 0
