#!/bin/bash
#remove enode
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
LOG="remove_capacity.log"



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

function remove_enode {
  curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X DELETE -d '{"async":true}' https://$EMS_ADDRESS/api/enodes/$1 >> $LOG 2>&1
}

function job_status {
  while true; do
    STATUS=`curl -k -s -b $SESSION_FILE --request GET --url "https://$EMS_ADDRESS/api/control_tasks/recent?task_name=$1" | grep status | cut -d , -f 7 | cut -d \" -f 4`
    echo -e  "$1 : $STATUS " | tee -a $LOG
    if [[ $STATUS == "success" ]]; then
      echo -e "$1 Complete! \n" | tee -a $LOG
      #incref enode ID to remove
      num=`cat enodes.txt`; ((num=num+1)); echo $num > enodes.txt
      sleep 5
      break
    fi
    if [[ $STATUS == "error" ]]; then
      echo -e "$1 Failed. Exiting..\n" | tee -a $LOG
      exit 1
    fi
    sleep 20
  done
}

# remove capacity
function remove_capacity {
  if [[ $NUM_OF_VMS == 0 ]]; then
    echo -e "0 VMs specified, skipping\n"
  else
    remove_enode `cat enodes.txt`
    job_status "remove"
  fi
}

#main
establish_session $PASSWORD
remove_capacity
