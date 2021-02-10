initNode() {
  mkdir -p /data/redis/{data,conf,run,logs}
  mkdir -p /data/sentinel/{data,conf,run,logs}
  chown -R redis.svc /data/redis
  chown -R redis.svc /data/sentinel
  execute updateConf
  execute _initNode
  execute _initCluster
}

getNodeCount() {
  wc -l $LIST_NODES_File
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

getMyRole() {
  /opt/redis/current/redis-cli -h 127.0.0.1 -p ${REDIS_PORT} info Replication |\
  awk -F ':'  '$1 == "role" {print $2}'
}

updateConf() {
  # 更新".master"里集群相关配置
  local nodeMaster=$(findMaster)
  updateRedisConfMaster $nodeMaster
  updateSentinelConfMaster $nodeMaster
  /opt/app/current/bin/tmpl/redis.sh
}

updateRedisConfMaster() {
  # 更新redis集群信息到".master"文件里
  local masterHost=$1 quorum=$(expr $(echo $LIST_NODES | wc -w) / 2  + 1)
  if [ -z "$masterHost" ]; then
    > ${SENTINEL_CONF}.master
  else
    echo "slaveof $masterHost $REDIS_PORT" > ${REDIS_CONF}.master 
  fi
}

updateSentinelConfMaster() {
  # 更新Sentinel集群信息到".master"文件里
  local masterHost=$1 quorum=$(expr $(echo $LIST_NODES | wc -w) / 2  + 1)
  [ -z "$masterHost" ] && masterHost="$MY_IP "
  echo "sentinel monitor $CLUSTER_ID $masterHost $REDIS_PORT $quorum" > ${SENTINEL_CONF}.master
}


findMaster() {
  # 用于寻找主节点使用
  isClusterInitialized || [ "$MY_SID" == "1" ] && return 0
  [ "$(getNodeCount)" == "1" ] && return 0
  [ -f "${REDIS_CONF}.master" ] && [ ! -s "${REDIS_CONF}.master" ] && return 0
  local info
  for info in $LIST_NODES; do
    local host=${info#*|}
    if nc -nz -w 1 $host $REDIS_PORT; then
      /opt/redis/current/redis-cli -h ${host} -p ${REDIS_PORT} info Replication > /tmp/infoRepl.tmp
      local masterHost
      if grep -wq "role:master" /tmp/infoRepl.tmp; then
        masterHost="$host"
      else
        masterHost=$(awk -F: '$1 == "master_host" {print $2}' /tmp/infoRepl.tmp)
      fi
      [[ "$masterHost" == "$MY_IP" ]] && masterHost=""
      echo -n $masterHost
      /bin/rm /tmp/infoRepl.tmp -f
      return 0
    fi
  done
  if ! isClusterInitialized && [ "$MY_SID" != "1" ] ; then
    awk -F "|" '$1==1{print $2}' $LIST_NODES_File
  else
    return 1
  fi
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
  local ip NodesIPs=$(awk -v sid=$MY_SID -F "|" '$1 != sid{print $2}' $LIST_NODES_File)
  while true
  do
    local w="off"
    for ip in $NodesIPs; do
      # echo "NodesIPs $ip $REDIS_PORT"
      if nc -nz -w 1 $ip $REDIS_PORT ; then
        w="on"
        break
      fi
    done
    [ "$1" == "$w" ] && break
    sleep 1
  done
  echo ok
}

stop() {
  execute updateConf
  [[ "$(getMyRole)" == "master"* ]] && waitNode off
  execute _stop
}

destroy() {
  [[ "$(getMyRole)" == "master"* ]] && /opt/redis/current/redis-cli -p ${SENTINEL_PORT} SENTINEL failover ${CLUSTER_ID}
}
