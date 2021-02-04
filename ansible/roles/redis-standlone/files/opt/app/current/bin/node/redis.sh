initNode() {
  mkdir -p /data/redis/data
  chown -R redis.svc /data/redis
  _initNode
}

measure() {
  echo '{"connections": '$(netstat -lanp | grep $MY_IP:80 | grep ESTABLISHED | wc -l)'}'
}
