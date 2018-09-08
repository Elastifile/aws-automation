#!/bin/bash
#add capacity
#Script to configure Elastifile EManage (EMS) Server, and deploy cluster of ECFS virtual controllers (vheads) in Amazon Web Services

set -u

usage() {
  cat << E_O_F
Usage:
  -a ems ip address
  -n  number of vhead instances (cluster size)
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
LOG="add_capacity.log"



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

# Kickoff a create vhead instances job
function create_instances {
  echo -e "Creating $NUM_OF_VMS ECFS instances\n" | tee -a $LOG
  curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X POST -d '{"instances":'$1',"async":true,"auto_start":true}' https://$EMS_ADDRESS/api/hosts/create_instances >> $LOG 2>&1
}

# Function to check running job status
function job_status {
  while true; do
    STATUS=`curl -k -s -b $SESSION_FILE --request GET --url "https://$EMS_ADDRESS/api/control_tasks/recent?task_type=$1" | grep status | cut -d , -f 7 | cut -d \" -f 4`
    echo -e  "$1 : $STATUS " | tee -a $LOG
    if [[ $STATUS == "success" ]]; then
      echo -e "$1 Complete! \n" | tee -a $LOG
      sleep 5
      break
    fi
    if [[ $STATUS == "error" ]]; then
      echo -e "$1 Failed. Exiting..\n" | tee -a $LOG
      exit 1
    fi
    sleep 10
  done
}


# Provision  and deploy
function add_capacity {
  if [[ $NUM_OF_VMS == 0 ]]; then
    echo -e "0 VMs specified, skipping\n"
  else
    create_instances $NUM_OF_VMS
    job_status "create_instances_job"
  fi
}

# Main
add_capacity
