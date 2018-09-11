#!/bin/bash
#get system statistics
#Script to configure Elastifile EManage (EMS) Server, and deploy cluster of ECFS virtual controllers (vheads) in Amazon Web Services

set -u

usage() {
  cat << E_O_F
Usage:
  -a ems ip address
E_O_F
  exit 1
}

#variables
SESSION_FILE=session.txt
PASSWORD=`cat password.txt | cut -d " " -f 1`
EMS_ADDRESS=111.222.333.444
EMS_NAME=elastifile-storage
SETUP_COMPLETE="false"
AUTOMATED="true"
NUM_OF_VMS=1
LOG="get_capacity.log"



while getopts "h?:a:n:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    a)  EMS_ADDRESS=${OPTARG}
        ;;
    n)  NUM_OF_VMS=${OPTARG}
        [ ${NUM_OF_VMS} -eq ${NUM_OF_VMS} ] || usage
        ;;
    esac
done

EMS_HOSTNAME="$EMS_NAME.local"

#output variables to log
echo "EMS_ADDRESS: $EMS_ADDRESS" | tee $LOG
echo "EMS_NAME: $EMS_NAME" | tee -a $LOG
echo "EMS_HOSTNAME: $EMS_HOSTNAME" | tee -a $LOG
echo "NUM_OF_VMS: $NUM_OF_VMS" | tee -a $LOG

#set -x

#establish https session
function establish_session {
echo -e "Establishing https session..\n" | tee -a $LOG
curl -k -D $SESSION_FILE -H "Content-Type: application/json" -X POST -d '{"user": {"login":"admin","password":"'$1'"}}' https://$EMS_ADDRESS/api/sessions >> $LOG 2>&1
}

#get capacity
establish_session $PASSWORD
curl -k -b $SESSION_FILE --request GET --url "https://$EMS_ADDRESS/api/system_statistics" | tee -a $LOG
