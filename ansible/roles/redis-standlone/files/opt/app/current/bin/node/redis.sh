

initNode() {
  mkdir -p /data/redis/{data,conf,run}
  mkdir -p /data/sentinel/{data,conf,run,tmp}
  chown -R redis.svc /data/redis
  chown -R redis.svc /data/sentinel
  _initNode
}

measure() {
  echo '{"connections": '$(netstat -ntp | awk -v ip="$MY_IP:$MY_PORT" '$6=="ESTABLISHED" && $5 == ip ' | wc -l)'}'
}

startSvc() {
  if [ "${1%%/*}" == "redis-server" ]; then
    echo "start ${1%%/*}"
    /opt/redis/current/redis-server /data/redis/conf/redis.conf
  else
    echo '_startSvc'
    _startSvc ${1%%/*}
  fi
  touch $APPCTL_CLUSTER_FILE
  touch $APPCTL_NODE_FILE
}

stopSvc() {
  echo "stop ${1%%/*}"
  if [ "${1%%/*}" == "redis-server" ]; then
    if [ -f '/data/redis/run/redis.pid' ]; then
      local mainpid=$(cat /data/redis/run/redis.pid)
      /bin/kill -15 $mainpid || /bin/kill -9 $mainpid
      tail --pid=$mainpid -f /dev/null
    fi
  else
    _startSvc ${1%%/*}
  fi
}

checkSvc()
{
  if [ "${1%%/*}" == "redis-server" ]; then
    echo "checkSvc redis-server"
    /opt/redis/current/redis-cli -h 127.0.0.1 -p ${1#*:} ping
  else
    _checkSvc ${1}
  fi

}