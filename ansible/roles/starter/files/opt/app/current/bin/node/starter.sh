initNode() {
  mkdir -p /data/caddy/data
  chown -R caddy.svc /data/caddy
  local readonly htmlFile=/data/caddy/data/index.html
  [ -e "$htmlFile" ] || ln -s /opt/app/current/conf/caddy/index.html $htmlFile
  _initNode
}

measure() {
  echo '{"connections": '$(netstat -lanp | grep $MY_IP:80 | grep ESTABLISHED | wc -l)'}'
}
