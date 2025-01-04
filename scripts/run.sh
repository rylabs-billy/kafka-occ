#!/bin/bash 
set -e
DEBUG="NO"
if [ "${DEBUG}" == "NO" ]; then
  trap "cleanup $? $LINENO" EXIT
fi

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
    test:check
}

# build instance vars before cluster deployment
function build {
  local LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .label,.type,.region,.image))
  local LINODE_TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
  local KAFKA_VERSION="${KAFKA_VERSION}"
  local group_vars="${WORK_DIR}/group_vars/kafka/vars"
  local TEMP_ROOT_PASS=$(openssl rand -base64 32)

  test:check
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

function deploy { 
    echo "[info] running ansible playbooks"
    ansible-playbook -v -i hosts provision.yml && ansible-playbook -v -i hosts site.yml
}

## cleanup ##
function cleanup {
  if [ "$?" != "0" ]; then
    echo "Error: $BASH_COMMAND failed with exit code $?"
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

# test functions
function test:check {
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
  fi
}

function test:instance_info {
  # for provision.yml in check mode
  echo -e "info:\n  results:" > info.yml
  count=100

  for host in $(seq $CLUSTER_SIZE); do
    echo -e '    - {"instance": {"ipv4": ["127.1.0.'$count'", "127.2.0.'$count'"]}}' >> vars.yml
    ((count++))
  done
}

function test:provision {
  test:instance_info
  ansible-playbook -v -i hosts provision.yml --check --extra-vars "@info.yml"
}

function test:site {
  # run just a couple tagged tasks to write dependent vars and files...  
  ansible-playbook -v -i hosts provision.yml --tags test_vars --extra-vars "@info.yml"
  ansible-plabook -v -i hosts site.yml --become --tags test_files
  # then run site.yml in check mode
  ansible-playbook -vv -i hosts site.yml --become --check

}

function test {
  echo "[info] running ansible playbooks in check mode"
  build
  test:provision
  test:site
}

# main
case $1 in
    build) "$@"; exit;;
    deploy) "$@"; exit;;
    test) "$@"; exit;;
esac
