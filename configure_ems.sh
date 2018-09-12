#!/bin/bash
#configure ems
#Script to configure Elastifile EManage (EMS) Server, and deploy cluster of ECFS virtual controllers (vheads) in Amazon Web Services
#set EMS_ADDRESS and EMS_NAME to use standalone

set -u

usage() {
  cat << E_O_F
Usage:
  -a ems ip address
  -n ems name (eg. elastifile-storage)
  -c  configuration type: "local" "persistent"
  -s  number of vhead instances (cluster size)
E_O_F
  exit 1
}

#variables
SESSION_FILE=session.txt
PASSWORD=`cat password.txt | cut -d " " -f 1`
EMS_ADDRESS=2242
EMS_NAME=elastifile-storage
SETUP_COMPLETE="false"
AUTOMATED="true"
NUM_OF_VMS=3
LOG="configure_ems.log"



while getopts "h?:a:n:c:s:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    a)  EMS_ADDRESS=${OPTARG}
        ;;
    n)  EMS_NAME=${OPTARG}
        ;;
    c)  CONFIGTYPE=${OPTARG}
        [ "${CONFIGTYPE}" = "local" -o "${CONFIGTYPE}" = "persistent" ] || usage
        ;;
    s)  NUM_OF_VMS=${OPTARG}
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

#required when immediately invoking after EMS instance creation
function check_ems_ready {
  #loop function to wait for EMS to complete loading after instance creation
  while true; do
    emsresponse=`curl -k -s -D $SESSION_FILE -H "Content-Type: application/json" -X POST -d '{"user": {"login":"admin","password":"changeme"}}' https://$EMS_ADDRESS/api/sessions | grep created_at | cut -d , -f 8 | cut -d \" -f 2`
    echo -e "Waiting for EMS init...\n" | tee -a $LOG
    if [[ $emsresponse == "created_at" ]]; then
      sleep 30
      echo -e "EMS now ready!\n" | tee -a $LOG
      break
    fi
    sleep 10
  done
}

# Configure ECFS storage type

function set_storage_type {
  if [[ $1 == "local" ]]; then
    echo -e "Setting storage type $1..." | tee -a $LOG
    curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":false,"cloud_configuration_id":1}' https://$EMS_ADDRESS/api/cloud_providers/1 >> $LOG 2>&1
  elif [[ $1 == "persistent" ]]; then
    echo -e "Setting storage type $1..." | tee -a $LOG
    curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X PUT -d '{"id":1,"load_balancer_use":false,"cloud_configuration_id":2}' https://$EMS_ADDRESS/api/cloud_providers/1 >> $LOG 2>&1
  fi
}

function setup_ems {
  #establish_session changeme

  #accept EULA
  echo -e "\nAccepting EULA.. \n" | tee -a $LOG
  curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X POST -d '{"id":1}' https://$EMS_ADDRESS/api/systems/1/accept_eula >> $LOG 2>&1

  #configure EMS
  echo -e "Configure EMS Settings...\n" | tee -a $LOG

  curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X PUT -d '{"name":"'$EMS_NAME'","replication_level":2,"show_wizard":false,"name_server":"'$EMS_HOSTNAME'","eula":true}' https://$EMS_ADDRESS/api/systems/1 >> $LOG 2>&1

  echo -e "\nGet cloud provider id 1\n" | tee -a $LOG
  curl -k -s -b $SESSION_FILE --request GET --url "https://$EMS_ADDRESS/api/cloud_providers/1" >> $LOG 2>&1

  echo -e "\nValidate project configuration\n" | tee -a $LOG
  curl -k -s -b $SESSION_FILE --request GET --url "https://$EMS_ADDRESS/api/cloud_providers/1/validate" >> $LOG 2>&1

  if [[ $NUM_OF_VMS == 0 ]]; then
    echo -e "0 VMs configured, skipping set storage type.\n"
  else
    echo -e "Set storage type $CONFIGTYPE \n" | tee -a $LOG
    set_storage_type $CONFIGTYPE
  fi

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

# Create data containers
function create_data_container {
  if [[ $NUM_OF_VMS != 0 ]]; then
    echo -e "Create data container & 200GB NFS export /DC01/root\n" | tee -a $LOG
    curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X POST -d '{"name":"DC01","dedup":0,"compression":1,"soft_quota":{"bytes":214748364800},"hard_quota":{"bytes":214748364800},"policy_id":1,"dir_uid":0,"dir_gid":0,"dir_permissions":"755","data_type":"general_purpose","namespace_scope":"global","exports_attributes":[{"name":"root","path":"/","user_mapping":"remap_all","uid":0,"gid":0,"access_permission":"read_write","client_rules_attributes":[],"namespace_scope":"global","data_type":"general_purpose"}]}' https://$EMS_ADDRESS/api/data_containers >> $LOG 2>&1
  fi
}

# Provision  and deploy
function add_capacity {
  if [[ $NUM_OF_VMS == 0 ]]; then
    echo -e "0 VMs configured, skipping create instances\n"
  else
    create_instances $NUM_OF_VMS
    job_status "create_instances_job"
    echo "Start cluster deployment\n" | tee -a $LOG
    job_status "activate_emanage_job"
  fi
}

function change_password {
  echo -e "Updating password...\n" | tee -a $LOG
  #update ems password
  curl -k -b $SESSION_FILE -H "Content-Type: application/json" -X PUT -d '{"user":{"id":1,"login":"admin","first_name":"Super","email":"admin@example.com","current_password":"changeme","password":"'$PASSWORD'","password_confirmation":"'$PASSWORD'"}}' https://$EMS_ADDRESS/api/users/1 >> $LOG 2>&1
  echo -e  "Establish new https session using updated PASSWORD...\n" | tee -a $LOG
  establish_session $PASSWORD
}

function reset_enodes_count {
  echo "1" > enodes.txt
}

# Main
if [ "$AUTOMATED" = "true" ]; then
  check_ems_ready
fi
setup_ems
add_capacity
create_data_container
change_password
reset_enodes_count
