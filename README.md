# Automate Elastifile ECFS via REST API

REST calls are HTTPS (443) to the public IP of EMS. Ensure project firewall/security group rules allow 443 (ingress) from wherever these are run.

## Components:

**configure_ems.sh**
Bash script to configure Elastifile eManage (EMS) Server via Elastifile JSON REST API. EMS will deploy cluster of ECFS virtual controllers (vheads).

**add_capacity.sh**
Add nodes to cluster

**query_ecfs.sh**
Get cluster capacity and performance

**remove_capacity.sh**
Remove nodes from cluster

**password.txt**
Plaintext file with EMS password
