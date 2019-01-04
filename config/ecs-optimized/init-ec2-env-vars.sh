echo `date`: Begin user data script
export LOCAL_BINDIR=/usr/local/bin
#DELETE EXISTING AWS ECS CONFIG FILE
rm -f /var/lib/ecs/data/ecs_agent_data.json
source my-ami-functions.sh
instanceTags=$(getInstanceTags)
tags_to_env "$instanceTags"
tags_to_eip
tags_to_dns
install_swap_file
install_volume
install_efs
remove_health_webserver
copy_public_keys
echo "ECS_CLUSTER=$ECS_CLUSTER" >  /etc/ecs/ecs.config
echo "ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=10m" >> /etc/ecs/ecs.config
monit reload
stop ecs
start ecs
echo `date`: Completed user data script
