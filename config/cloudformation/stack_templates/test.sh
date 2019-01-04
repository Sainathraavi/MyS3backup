#!/bin/bash
#
# INIT SYSTEM FROM EC2 INSTANCE VARIABLES
#
/usr/bin/init-ec2-env-vars.sh

# restart nginx daily
cat << 'EOF' >> /etc/cron.daily/restart-nginx.sh
#!/bin/bash
docker exec $(docker ps | grep nginx | awk '{print $1}') /usr/sbin/nginx -s reload
EOF
chmod +x /etc/cron.daily/restart-nginx.sh
