#!/bin/bash

# scripts/app-deps.sh
# configures test environment for ansible check mode

function playbook_deps {
  echo "[info] installing playbook dependencies"
  # install yq
  VERSION=v4.44.6
  BINARY=yq_linux_amd64
  curl -sLO "https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz"
  tar xvf ${BINARY}.tar.gz && mv ${BINARY} /usr/bin/yq

  # required files from apt install
  apt install fail2ban -y
}

function kafka_deps {
  echo "[info] configure kafka dependencies"
  defaults="roles/kafka/defaults/main.yml"

  # add kafka user and group
  useradd --system -s /usr/bin/nologin -m $(cat $defaults | yq .kafka_data_directory)
  id kafka

  # write dirs and vars from roles/kafka/defaults/main.yml
  kafka_file_list=($(
    cat $defaults \
    | grep -Ev '#|---' \
    | IFS='\n' awk '{print $2}' \
    | tr '\n' ' '
    ))

  for file in "${kafka_file_list[@]}"; do
    if [[ "$file" == *"kafka"* ]]; then
      mkdir -p $file
      chown -R kafka: $file
    else
      export kafka_version="$file"
    fi
  done

  curl -s -o "/tmp/kafka_2.13-${kafka_version}.tgz" \
    "https://downloads.apache.org/kafka/${kafka_version}/kafka_2.13-${kafka_version}.tgz"
}
