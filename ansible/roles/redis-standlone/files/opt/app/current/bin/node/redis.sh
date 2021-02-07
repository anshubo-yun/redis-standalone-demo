
killServer() {
    if [ -f '$1' ]; then
      local mainpid=$(cat $1)
      /bin/kill -15 $mainpid || /bin/kill -9 $mainpid
      tail --pid=$mainpid -f /dev/null
    fi

}

initNode() {

  mkdir -p /data/redis/{data,conf,run}
  mkdir -p /data/sentinel/{data,conf,run,tmp}
  chown -R redis.svc /data/redis
  chown -R redis.svc /data/sentinel
  _initNode
  master_host=$(findMaster)
  if [ "$master_host" != "master" ]; then
  fi
  start
  touch $APPCTL_CLUSTER_FILE
  touch $APPCTL_NODE_FILE
}

measure() {
  echo '{"connections": '$(netstat -ntp | awk -v ip="$MY_IP:$redis_PORT" '$6=="ESTABLISHED" && $5 == ip ' | wc -l)'}'
}

findMaster() {
  # 用于寻找主节点使用
  if [ "$MY_SID" == "1" ] && ! isClusterInitialized ; then
      echo "master"
  else
    local info
    for info in $(echo $ADDING_LIST); do
      local host=${info#*|} port=${REDIS_PORT}
      if [ ${info%%|*} != ${MY_SID} ] && nc -nz $host $port; then
        master_host=$(/opt/redis/current/redis-cli -h $host -p $port info Replication |\
                      awk -F: '$1=="master_host" || /role:master/{print $2}')
        if [[ "$master_host" == "master"* ]] ; then
          master_host="$host"
        fi
        echo  "$master_host"
        return 0
      fi
    done
  fi
}

startSvc() {
  if [ "${1%%/*}" == "redis-server" ]; then
    /opt/redis/current/redis-server /data/redis/conf/redis.conf
    # /opt/redis/current/redis-cli -h 172.22.49 -p  slaveof 172.22.4.9 6379
  elif [ "${1%%/*}" == "redis-sentinel" ]; then
    /opt/redis/current/redis-sentinel /data/sentinel/conf/sentinel.conf
  fi
  md5sum $CONF_REDIS > /data/conf.md5
}


stopSvc() {
  if [ "${1%%/*}" == "redis-server" ]; then
    killServer '/data/redis/run/redis.pid'
  elif [ "${1%%/*}" == "redis-sentinel" ]; then
    killServer '/data/sentinel/run/sentinel.pid'
  else
    _startSvc ${1%%/*}
  fi
}

checkSvc() {
  if [ "${1%%/*}" == "redis-"* ]; then
    /opt/redis/current/redis-cli -h 127.0.0.1 -p ${1#*:} ping
  else
    _checkSvc ${1}
  fi

}

reload() {
  if [ -f "$CONF_MD5" ] && ( ! md5sum -c $CONF_MD5 ) ; then
    _reload
  fi
}