#!/bin/bash
set -e
DEBUG="NO"
if [ "${DEBUG}" == "NO" ]; then
  trap "cleanup $? $LINENO" EXIT
fi

## deployment variables
# <UDF name="kafka_version" label="Kafka version" default="3.8.0" oneof="3.8.0" />
# <UDF name="token_password" label="Your Linode API token" />
# <UDF name="sudo_username" label="The limited account user" default='admin'>
# <UDF name="client_count" label="Number of clients connecting to Kafka">
# <UDF name="cluster_size" label="Kafka cluster size" oneOf="3,5,7">
# <UDF name="clusterheader" label="Cluster Settings" default="Yes" header="Yes">
# <UDF name="add_ssh_keys" label="Add Account SSH Keys to All Nodes?" oneof="yes,no"  default="yes" />

# ssl variables
# <UDF name="sslheader" label="SSL Information" header="Yes" default="Yes" required="Yes">
# <UDF name="country_name" label="Details for self-signed SSL certificates: Country or Region" oneof="AD,AE,AF,AG,AI,AL,AM,AO,AQ,AR,AS,AT,AU,AW,AX,AZ,BA,BB,BD,BE,BF,BG,BH,BI,BJ,BL,BM,BN,BO,BQ,BR,BS,BT,BV,BW,BY,BZ,CA,CC,CD,CF,CG,CH,CI,CK,CL,CM,CN,CO,CR,CU,CV,CW,CX,CY,CZ,DE,DJ,DK,DM,DO,DZ,EC,EE,EG,EH,ER,ES,ET,FI,FJ,FK,FM,FO,FR,GA,GB,GD,GE,GF,GG,GH,GI,GL,GM,GN,GP,GQ,GR,GS,GT,GU,GW,GY,HK,HM,HN,HR,HT,HU,ID,IE,IL,IM,IN,IO,IQ,IR,IS,IT,JE,JM,JO,JP,KE,KG,KH,KI,KM,KN,KP,KR,KW,KY,KZ,LA,LB,LC,LI,LK,LR,LS,LT,LU,LV,LY,MA,MC,MD,ME,MF,MG,MH,MK,ML,MM,MN,MO,MP,MQ,MR,MS,MT,MU,MV,MW,MX,MY,MZ,NA,NC,NE,NF,NG,NI,NL,NO,NP,NR,NU,NZ,OM,PA,PE,PF,PG,PH,PK,PL,PM,PN,PR,PS,PT,PW,PY,QA,RE,RO,RS,RU,RW,SA,SB,SC,SD,SE,SG,SH,SI,SJ,SK,SL,SM,SN,SO,SR,SS,ST,SV,SX,SY,SZ,TC,TD,TF,TG,TH,TJ,TK,TL,TM,TN,TO,TR,TT,TV,TW,TZ,UA,UG,UM,US,UY,UZ,VA,VC,VE,VG,VI,VN,VU,WF,WS,YE,YT,ZA,ZM,ZW" />
# <UDF name="state_or_province_name" label="State or Province" example="Example: Pennsylvania" />
# <UDF name="locality_name" label="Locality" example="Example: Philadelphia" />
# <UDF name="organization_name" label="Organization" example="Example: Akamai Technologies" />
# <UDF name="email_address" label="Email Address" example="Example: webmaster@example.com" />
# <UDF name="ca_common_name" label="CA Common Name" example="Example: Kafka RootCA" />

# git repo
export GIT_REPO="https://github.com/akamai-compute-marketplace/kafka-occ.git"
export WORK_DIR="/tmp/linode" 
export UUID=$(uuidgen | awk -F - '{print $1}')

# enable logging (when not in check mode)
if [ -z "${CHECK_MODE}" ]; then
  exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1
fi

function cleanup {
  if [ "$?" != "0" ] || [ "$SUCCESS" == "true" ]; then
    cd ${HOME}
    if [ -d ${WORK_DIR} ]; then
      rm -rf ${WORK_DIR}
    fi
    if [ -f "/usr/local/bin/run" ]; then
      rm /usr/local/bin/run
    fi
  fi
}

# validate client_count. Hard fail if non-numeric value is entered.
if [[ ${CLIENT_COUNT} =~ ^-?[1-9][0-9]*$ ]]; then
  echo "valid count entered for client count"
else
  echo "[fatal] invalid entry for client count '${CLIENT_COUNT}'. Rerun deployment using an interger"
  exit 1
fi

# cluster functions
function add_privateip {
  echo "[info] Adding instance private IP"
  curl -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
      -X POST -d '{
        "type": "ipv4",
        "public": false
      }' \
      https://api.linode.com/v4/linode/instances/${LINODE_ID}/ips
}

function get_privateip {
  curl -s -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
   https://api.linode.com/v4/linode/instances/${LINODE_ID}/ips | \
   jq -r '.ipv4.private[].address'
}

function configure_privateip {
  if [ -n "${CHECK_MODE}" ]; then
    LINODE_IP="192.168.0.2"
  else
    LINODE_IP=$(get_privateip)
  fi

  if [ ! -z "${LINODE_IP}" ]; then
    echo "[info] Linode private IP present"
  else
    echo "[warn] No private IP found. Adding.."
    add_privateip
    LINODE_IP=$(get_privateip)
    ip addr add ${LINODE_IP}/17 dev eth0 label eth0:1
  fi
}

function rename_provisioner {
  echo "[info] renaming the provisioner"
  if [ -n "${CHECK_MODE}" ]; then
    export INSTANCE_PREFIX="kafka-occ1-${UUID}"
  else
    INSTANCE_PREFIX=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .label)
    export INSTANCE_PREFIX=${INSTANCE_PREFIX}
    curl -s -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
      -X PUT -d "{
        \"label\": \"${INSTANCE_PREFIX}1-${UUID}\"
      }" https://api.linode.com/v4/linode/instances/${LINODE_ID}
  fi
}

function setup {
  # install dependancies
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y git python3 python3-pip python3-venv jq

  # rename provisioner and configure private IP if not present
  rename_provisioner
  configure_privateip 

  if [ "${ADD_SSH_KEYS}" == "yes" ]; then
    if [ ! -d ~/.ssh ] ; then
      mkdir ~/.ssh
    fi

    if [ -n "${CHECK_MODE}" ]; then
      echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5A bthompson@linode.com" > ${HOME}/.ssh/authorized_keys
    else
      curl -sH "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
        https://api.linode.com/v4/profile/sshkeys \
        | jq -r .data[].ssh_key > /root/.ssh/authorized_keys
    fi
  fi

  # clone repo and set up ansible environment
  git clone ${GIT_REPO} ${WORK_DIR}
  # for a single testing branch
  # git clone -b ${BRANCH} ${GIT_REPO} ${WORK_DIR}

  # venv
  cd ${WORK_DIR}

  #pip3 install virtualenv
  python3 -m venv env
  source env/bin/activate
  pip install pip --upgrade
  pip install -r requirements.txt
  ansible-galaxy install -r collections.yml

  # copy run script
  cp scripts/run.sh /usr/local/bin/run
  chmod +x /usr/local/bin/run
}

function installation_complete {
  echo "Installation Complete"
}

# main
setup

if [ -n "${CHECK_MODE}" ]; then
  run test
else
  run build
  run deploy && installation_complete
fi

if [ "${DEBUG}" == "NO" ]; then
  cleanup
fi
