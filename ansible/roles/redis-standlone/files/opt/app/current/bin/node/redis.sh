initNode() {
  mkdir -p /data/redis/{data,conf,run,logs}
  mkdir -p /data/sentinel/{data,conf,run,logs}
  chown -R redis.svc /data/redis
  chown -R redis.svc /data/sentinel
  # execute updateConf
  if ! isClusterInitialized; then
      ( [ "$MY_SID" == "1" ] && echo "0:$MY_IP" || awk -F: '$1==1' $LIST_NODES_File  ) > $CLUSTER_MASTER_FILE
  fi
  execute _initCluster
  execute _initNode
}

measure() {
  echo '{"connections": '$(netstat -ntp | awk -v ip="$MY_IP:$REDIS_PORT" '$6=="ESTABLISHED" && $5 == ip ' | wc -l)'}'
}

killServer() {
  if [ -f "$1" ]; then
    local mainpid=$(cat $1)
    /bin/kill -15 $mainpid || /bin/kill -9 $mainpid
    tail --pid=$mainpid -f /dev/null
  fi
}

isMaster() {
  local host=$([ -n "$1" ] && echo "$1" ||  echo "127.0.0.1" )
  /opt/redis/current/redis-cli -h ${host} -p ${REDIS_PORT} info Replication |\
  grep -wq "role:master"
}

updateConf() {
  # 更新".master"里集群相关配置
  # local nodeMaster=$(awk -v sid=$(findMaster) -F: '$1!=sid{pirnt $2}' $LIST_NODES_File )
  findMaster
  /opt/app/current/bin/tmpl/redis.sh
}


findMaster() {
  # 用于寻找主节点使用
  for info in $(awk -v sid=$MY_SID -F: '$1!=sid' $LIST_NODES_File); do
    local msid=${info%:*} host=${info#*:}
    if nc -nz -w 1 $host $REDIS_PORT && isMaster "$host"; then 
      echo "$msid" > $CLUSTER_MASTER_FILE
      break
    fi
  done
  # cat $CLUSTER_MASTER_FILE
}

createHashConf() {
  awk '$1 != "slaveof"' ${REDIS_CONF} | md5sum | awk '{print $1}' > ${CONF_MD5}
}

checkHashConf() {
  if [ -f "${REDIS_CONF} " ]; then
    [ "$(awk '$1 != "slaveof"' ${REDIS_CONF} | md5sum | awk '{print $1}')" == "$(cat  ${CONF_MD5})" ]
  fi
}

startSvc() {
  if [ "${1%%/*}" == "redis-server" ]; then
    /opt/redis/current/redis-server ${REDIS_CONF}
    execute createHashConf
    # /opt/redis/current/redis-cli -h 172.22.49 -p  slaveof 172.22.4.9 6379
  elif [ "${1%%/*}" == "redis-sentinel" ]; then
    /opt/redis/current/redis-sentinel ${SENTINEL_CONF}
  else
    execute _startSvc ${1}
  fi
}

stopSvc() {
  if [ "${1%%/*}" == "redis-server" ]; then
    execute killServer '/data/redis/run/redis.pid'
  elif [ "${1%%/*}" == "redis-sentinel" ]; then
    execute killServer '/data/sentinel/run/sentinel.pid'
  else
    execute _stopSvc ${1}
  fi
}

checkSvc() {
  if [[ "${1%%/*}" == "redis-"* ]]; then
    /opt/redis/current/redis-cli -h 127.0.0.1 -p ${1#*:} ping
  else
    execute _checkSvc ${1}
  fi
}

reload() {
  if ! checkHashConf ; then
    execute _reload
  fi
}

waitNode() {
  local ip status
  while true
  do
    status="off"
    for ip in $(awk -v sid=$MY_SID -F: '$1 != sid{print $2}' $LIST_NODES_File); do
      # echo "NodesIPs $ip $REDIS_PORT"
      if nc -nz -w 1 $ip $REDIS_PORT ; then
        status="on"
        break
      fi
    done
    [ "$1" == "$status" ] && break
    sleep 1
  done
}

stop() {
  execute updateConf
  isMaster && waitNode off
  execute _stop
}

destroy() {
  isMaster && /opt/redis/current/redis-cli -p ${SENTINEL_PORT} SENTINEL failover ${CLUSTER_ID}
}
