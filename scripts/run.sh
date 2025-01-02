#!/bin/bash 
set -e
DEBUG="NO"
if [ "${DEBUG}" == "NO" ]; then
  trap "cleanup $? $LINENO" EXIT
fi

function check_mode_deps {
  if [ $"${CHECK_MODE}" == "1" ]; then
    # get name of caller (parent) function
    caller="${FUNCNAME[1]}"

    # list of dependent apt packages
    # using 'list' type with a 'for loop' for future extendibility and reuse
    deps=("fail2ban")
    for file in "${deps[@]}"; do
      apt install $file
    done
    
    if [ "${caller}" == "controller_sshkey" ]; then
      echo $ANSIBLE_SSH_PUB_KEY >> ${HOME}/.ssh/authorized_keys
    fi

    if [ "${caller}" == "build" ]; then
      export LINODE_PARAMS=("${INSTANCE_PREFIX}" "g6-standard-8" "us-ord" "linode/ubuntu22.04")
      export LINODE_TAGS="test"
    fi
  fi
}

# controller temp sshkey
function controller_sshkey {
    ssh-keygen -o -a 100 -t ed25519 -C "ansible" -f "${HOME}/.ssh/id_ansible_ed25519" -q -N "" <<<y >/dev/null
    export ANSIBLE_SSH_PUB_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519.pub)
    export ANSIBLE_SSH_PRIV_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519)
    export SSH_KEY_PATH="${HOME}/.ssh/id_ansible_ed25519"
    chmod 700 ${HOME}/.ssh
    chmod 600 ${SSH_KEY_PATH}
    eval $(ssh-agent)
    ssh-add ${SSH_KEY_PATH}
    check_mode_deps
}

# build instance vars before cluster deployment
function build {
  local LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .label,.type,.region,.image))
  local LINODE_TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
  local KAFKA_VERSION="${KAFKA_VERSION}"
  local group_vars="${WORK_DIR}/group_vars/kafka/vars"
  local TEMP_ROOT_PASS=$(openssl rand -base64 32)

  check_mode_deps
  controller_sshkey

  cat << EOF >> ${group_vars}
# user vars
sudo_username: ${SUDO_USERNAME}
token: ${TOKEN_PASSWORD}
# deployment vars
uuid: ${UUID}
ssh_keys: ${ANSIBLE_SSH_PUB_KEY}
instance_prefix: ${INSTANCE_PREFIX}
type: ${LINODE_PARAMS[1]}
region: ${LINODE_PARAMS[2]}
image: ${LINODE_PARAMS[3]}
linode_tags: ${LINODE_TAGS}
root_pass: ${TEMP_ROOT_PASS}
kafka_version: ${KAFKA_VERSION}
cluster_size: ${CLUSTER_SIZE}
controller_count: 3
client_count: ${CLIENT_COUNT}
add_ssh_keys: '${ADD_SSH_KEYS}'

# ssl config
country_name: ${COUNTRY_NAME}
state_or_province_name: ${STATE_OR_PROVINCE_NAME}
locality_name: ${LOCALITY_NAME}
organization_name: ${ORGANIZATION_NAME}
email_address: ${EMAIL_ADDRESS}
ca_common_name: ${CA_COMMON_NAME}
EOF
}

function test:instance_info {
  # for provision.yml in check mode
  cat <<EOF > info.yml
info:
  results:
    - {"instance": {"ipv4": ["127.1.0.100", "127.2.0.100"]}}
    - {"instance": {"ipv4": ["127.1.0.101", "127.2.0.101"]}}
    - {"instance": {"ipv4": ["127.1.0.102", "127.2.0.102"]}}
EOF
}

function test:inventory {
  cat <<EOF > hosts
# ansible inventory
# BEGIN KAFKA INSTANCES
[kafka]
localhost ansible_connection=local user=$(whoami) role='controller and broker'
127.1.0.101 role='controller and broker'
127.1.0.103 role='controller and broker'
# END KAFKA INSTANCES
EOF
}

function deploy { 
    echo "[info] running ansible playbooks"
    ansible-playbook -v -i hosts provision.yml && ansible-playbook -v -i hosts site.yml
}

function test {
  echo "[info] running ansible playbooks in check mode"
  build

  # dry run provision.yml
  test:instance_info
  ansible-playbook -v -i hosts provision.yml --check --extra-vars "@info.yml"

  # dry run site.yml
  # test:inventory
  # run provision.yml without check mode to populate our vars and hosts files...
  ansible-playbook -v -i hosts provision.yml --tags test_vars --extra-vars "@info.yml"
  # then check site.yml
  ansible-playbook -vvv -i hosts site.yml --check --extra-vars "user=$(whoami) ansible_user=$(whoami)"
}

## cleanup ##
function cleanup {
  if [ "$?" != "0" ]; then
    if [ -n "$GITHUB_ENV" ]; then
      echo "PLAYBOOK_FAILED=1" | tee -a $GITHUB_ENV
    fi
    echo "PLAYBOOK FAILED. See /var/log/stackscript.log for details."
    rm ${HOME}/.ssh/id_ansible_ed25519{,.pub}
    destroy
    exit 1
  fi
}

function destroy {
  echo "[info] destroying instances except provisioner node" 
  ansible-playbook destroy.yml
}

# main
case $1 in
    build) "$@"; exit;;
    deploy) "$@"; exit;;
    test) "$@"; exit;;
esac
