#!/bin/bash
 case $1 in
    start)
       test -e /var/run/health-webserver.pid && kill `cat /var/run/health-webserver.pid`
       exec /usr/local/bin/health-webserver.py 2>&1 | /usr/bin/logger -t health-webserver & ;;
     stop)
     test -e /var/run/health-webserver.pid && kill `cat /var/run/health-webserver.pid` ;;
     *)
       echo "usage: health-webserver {start|stop}" ;;
 esac
 exit 0
