#!/bin/bash

# scripts/app-deps.sh
# configures test environment for ansible check mode

function test:check_mode_deps {
  if [ $"${CHECK_MODE}" == "1" ]; then
    # get name of caller (parent) function
    caller="${FUNCNAME[1]}"
    user=$(whoami)

    if [ "${caller}" == "controller_sshkey" ]; then
      [ "${user}" == 'root' ] && HOME_DIR="/root" || HOME_DIR="${HOME}"
      echo $ANSIBLE_SSH_PUB_KEY >> ${HOME_DIR}/.ssh/authorized_keys
    fi

    if [ "${caller}" == "build" ]; then
      export LINODE_PARAMS=("${INSTANCE_PREFIX}" "g6-standard-8" "us-ord" "linode/ubuntu22.04")
      export LINODE_TAGS="test"
    fi

    [ "${caller}" == "configure_privateip" ] && LINODE_IP="192.168.0.2"
    [ "${caller}" == "rename_provisioner" ] && export INSTANCE_PREFIX="kafka-occ1-${UUID}"
    [ "${caller}" == "setup" ] && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5A bthompson@linode.com" > ${HOME}/.ssh/authorized_keys
  fi
}

function test:packages {
  echo "[info] installing playbook dependencies"
  # install yq
  VERSION=v4.44.6
  BINARY=yq_linux_amd64
  curl -sLO "https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz"
  tar xvf ${BINARY}.tar.gz && mv ${BINARY} /usr/bin/yq

  # required files from apt install
  apt install fail2ban -y
}

# function test:ssl {
#   local vars_file="$1"
#   local ca_password=$(cat $vars_file | yq .ca_password)
#   local keystore_password=$(cat $vars_file | yq .keystore_password)
#   local truststore_password=$(cat $vars_file | yq .truststore_password)
  
#   for dir in "${!defaults[@]}"; do
#     [[ "${defaults[$file]}" == *"ssl_dir"* ]] && ssl_dir="${defaults[$dir]}"
#     [[ "${defaults[$file]}" == *"ca_dir"* ]] && ca_dir="${defaults[$dir]}"
#     [[ "${defaults[$file]}" == *"req_dir"* ]] && req_dir="${defaults[$dir]}"
#     [[ "${defaults[$file]}" == *"key_dir"* ]] && key_dir="${defaults[$dir]}"
#     [[ "${defaults[$file]}" == *"cert_dir"* ]] && cert_dir="${defaults[$dir]}"
#     [[ "${defaults[$file]}" == *"keystore"* ]] && keystore_dir="${defaults[$dir]}"
#     [[ "${defaults[$file]}" == *"truststore"* ]] && truststore_dir="${defaults[$dir]}"
#   done

#   # generate ca
#   openssl genrsa -aes128 -passout pass:$ca_password -out "${ca_dir}/ca-key" 4096

#   openssl req -key "${ca_dir}/ca_key" -passin pass:$ca_password  \
#     -subj "/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE_NAME/L=$LOCALITY_NAME\
#     /O=$ORGANIZATION_NAME/CN=$CA_COMMON_NAME/emailAddress=$EMAIL_ADDRESS" \
#     -addext "basicConstraints = critical, CA:true" \
#     -addtext "keyUsage = critical, keyCertSign" \
#     -new -out "$ca_dir/ca-csr"

#     openssl x509 -req -in careq.pem -extfile openssl.cnf -extensions v3_ca \
#        -signkey key.pem -out cacert.pem

#   openssl x509 -req -in "$ca_dir/ca-csr" -extensions v3_ca \
#     -signkey "$ca_dir/ca-key" -passin pass:$ca_password -days 365 \
#     -out "$ca_dir/ca-crt"

#   # server and client certs
#   for server in $(seq $CLUSTER_SIZE);
#   openssl genrsa -out "${key_dir}/ca-key" 4096
#   openssl genrsa -out "${key_dir}/ca-key" 4096



# - name: generate ca crt
#   community.crypto.x509_certificate:
#     path: '{{ kafka_ssl_ca_directory }}/ca-crt'
#     privatekey_path: '{{ kafka_ssl_ca_directory }}/ca-key'
#     privatekey_passphrase: '{{ ca_password }}'
#     csr_path: '{{ kafka_ssl_ca_directory }}/ca-csr'
#     selfsigned_not_after: +3650d
#     provider: selfsigned

# }

function test:defaults {
  local yaml_file="$1"
  local parsed=($(yq '.[] | ( select(kind == "scalar") | key + "=" + . )' $yaml_file))

  declare -A defaults
  for line in "${parsed[@]}"; do
    key=$(echo $line | awk -F= '{print $1}')
    value=$(echo $line | awk -F= '{print $2}')
    defaults["$key"]="$value"
  done

  kafka_file_list=()
  for file in "${!defaults[@]}"
    if [[ "${defaults[$file]}" == *"kafka"* ]]; then
      kafka_file_list+=("${defaults[$file]}")
    fi
  done
}

function test:kafka {
  echo "[info] configure kafka dependencies"
  defaults_file="roles/kafka/defaults/main.yml"
#   defaults_dir="roles/kafka/defaults/main.yml"
  home_dir=$(cat $defaults_file | yq .kafka_data_directory)
  test:defaults "${defaults_file}"
  
  # add kafka user and group
  useradd --system --user-group -s /usr/bin/nologin -m -d $home_dir kafka
  id kafka

  # write dirs and vars from roles/kafka/defaults/main.yml
#   kafka_file_list=($(
#     cat $defaults \
#     | grep -Ev '#|---' \
#     | IFS='\n' awk '{print $2}' \
#     | tr '\n' ' '
#     ))

  for file in "${kafka_file_list[@]}"; do
      mkdir -p $file
      chown -R kafka: $file
  done

  curl -s -o "/tmp/kafka_2.13-${KAFKA_VERSION}.tgz" \
    "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"

  # let the ansible playbook do some of this work for us.

}

# function test:group_vars {
#   # for provision.yml in check mode
#   cat <<EOF > vars.yml
# truststore_password: 4a3ab688-c959-11ef-b7ef-c3d2d00d00e9
# keystore_password: 4a3ab890-c959-11ef-b7f0-43b5a08a833c
# ca_password: 4a3ab8fe-c959-11ef-b7f1-8b5f5d5abd07
# sudo_password: 4a3ab962-c959-11ef-b7f2-9f75255196f2

function test:instance_info {
  # for provision.yml in check mode
  echo -e "info:\n  results:" > info.yml
  count=100

  for host in $(seq $CLUSTER_SIZE); do
    echo -e '    - {"instance": {"ipv4": ["127.1.0.'$count'", "127.2.0.'$count'"]}}' >> vars.yml
    ((count++))
  done
}

function test:instance_infos {
  # for provision.yml in check mode
  cat <<EOF > info.yml
info:
  results:
    - {"instance": {"ipv4": ["127.1.0.100", "127.2.0.100"]}}
    - {"instance": {"ipv4": ["127.1.0.101", "127.2.0.101"]}}
    - {"instance": {"ipv4": ["127.1.0.102", "127.2.0.102"]}}
EOF
}

# function test:inventory {
#   cat <<EOF > hosts
# # ansible inventory
# # BEGIN KAFKA INSTANCES
# [kafka]
# localhost ansible_connection=local user=root role='controller and broker'
# 127.1.0.101 role='controller and broker'
# 127.1.0.102 role='controller and broker'
# # END KAFKA INSTANCES
# EOF
# }

function test:provision {
  test:instance_info
  ansible-playbook -v -i hosts provision.yml --check --extra-vars "@info.yml"
}

function test:site {
  test:packages
  ansible-playbook -v -i hosts provision.yml --tags test_vars --extra-vars "@info.yml"
  ansible-plabook -v -i hosts site.yml --become --tags test_files
  ansible-playbook -vv -i hosts site.yml --become --check

}
function test {
  echo "[info] running ansible playbooks in check mode"
  build
  test:provision
  test:site
#   test:kafka
#   test:ssl

  # dry run provision.yml
  test:instance_info
  # sudo -i -u $(whoami)
  ansible-playbook -v -i hosts provision.yml --check --extra-vars "@info.yml"

  # dry run site.yml
  # test:inventory
  # run provision.yml without check mode to populate our vars and hosts files...
  ansible-playbook -v -i hosts provision.yml --tags test_vars --extra-vars "@info.yml"
  ansible-plabook -v -i hosts site.yml --become --tags test_files
  # then check site.yml
  ansible-playbook -vv -i hosts site.yml --become --check  #--extra-vars "@vars.yml"
  # ansible-playbook -vv -i hosts site.yml --become --check --extra-vars "user=$(whoami) ansible_user=$(whoami)"
}