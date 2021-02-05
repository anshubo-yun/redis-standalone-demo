

initNode() {
  mkdir -p /data/redis/{data,conf,run}
  mkdir -p /data/sentinel/{data,conf,run,tmp}
  chown -R redis.svc /data/redis
  chown -R redis.svc /data/sentinel
  _initNode
}

measure() {
  echo '{"connections": '$(netstat -lanp | grep $MY_IP:80 | grep ESTABLISHED | wc -l)'}'
}
