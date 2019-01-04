# Loads the Tags from the current instance
getRegion() {
  export EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
  export EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

}

trimSpaces() {
  arg=$1
  #To remove leading white spaces: sed 's/^ *//g'
  #To remove trailing white spaces: sed 's/ *$//g'
  arg=$(echo "$arg" | sed 's/^ *//g' | sed 's/ *$//g')
  echo $arg
}

getInstanceTags () {
  getRegion
  # get the instance ID for use with ec2 describe-tags
  export INSTANCE_ID=$(ec2-metadata | grep instance-id | awk '{print $2}')
  # Describe the tags of this instance
  $LOCAL_BINDIR/aws ec2 describe-tags --region $EC2_REGION --filters "Name=resource-id,Values=$INSTANCE_ID"

}

# Convert the tags to environment variables.
# Based on https://github.com/berpj/ec2-tags-env/pull/1
tags_to_env () {
  tags=$1

  for key in $(echo $tags | /usr/bin/jq -r ".[][].Key"); do
      value=$(echo $tags | /usr/bin/jq -r ".[][] | select(.Key==\"$key\") | .Value")
      key=$(echo $key | /usr/bin/tr '-' '_' | /usr/bin/tr '[:lower:]' '[:upper:]')
      value=$(trimSpaces $value)
      key=$(trimSpaces $key)
	if [[ $key != *"AWS:"* ]]
	then
          echo "Exporting $key=$value"
          export $key="$value"
          echo "export $key=$value" >> /home/ec2-user/.bashrc ;
        fi
    done
}


tags_to_eip () {
  if [[ -z ${ELASTIC_IP}  ]];
     then
  echo "ELASTIC_IP env variable is unset";
     else

        local INSTANCE_ID=$(ec2-metadata | grep instance-id | awk '{print $2}')
        getRegion
        echo "Associating EIP $ELASTIC_IP with EC2 instance $INSTANCE_ID"
        $LOCAL_BINDIR/aws ec2 associate-address --instance-id "$INSTANCE_ID" --region "$EC2_REGION" --allocation-id "$ELASTIC_IP"
        local EIP_INSTANCE=$(aws ec2 describe-addresses --allocation-ids $ELASTIC_IP --region $EC2_REGION --query "Addresses[0].{instance:InstanceId}" --output text)
        local count=0
        while [[ $EIP_INSTANCE != $INSTANCE_ID && $count -lt 12 ]]
        do
          count=$[count+1]
          sleep 15
          EIP_INSTANCE=$(aws ec2 describe-addresses --allocation-ids $ELASTIC_IP --region $EC2_REGION --query "Addresses[0].{instance:InstanceId}" --output text)

        done
        if [[ $count -lt 12 ]];
          then

            echo "Elastic IP $EIP_INSTANCE was successfully associated with instance $INSTANCE_ID"
            $LOCAL_BINDIR/aws ec2 describe-addresses --allocation-ids $ELASTIC_IP --region $EC2_REGION;
          else
            echo "Elastic IP $EIP_INSTANCE was NOT associated with instance $INSTANCE_ID";
        fi


  fi

}

tags_to_dns () {
  getRegion
  PRIVATE_IPV4=$(ec2-metadata | grep local-ipv4 | awk '{print $2}')
  if [[ -z ${ELASTIC_IP+x} ]];
     then
       PUBLIC_IPV4=$(ec2-metadata | grep public-ipv4 | awk '{print $2}');
     else
       PUBLIC_IPV4=$(aws ec2 describe-addresses --allocation-ids $ELASTIC_IP --region $EC2_REGION --query "Addresses[0].{instance:PublicIp}" --output text);

  fi

  if [[ -z ${PRIVATE_ZONEID+x} || -z ${PRIVATE_DNS+x} || -z ${TTL+x} || -z ${PRIVATE_IPV4+x} ]];
     then
	 echo "PRIVATE_ZONEID or PRIVATE_DNS or TTL are unset";
     else
        echo "Updating Route 53 PRIVATE ZONE record"
	set-dns.bash $PRIVATE_ZONEID $PRIVATE_DNS $TTL $PRIVATE_IPV4 $EC2_REGION;

  fi

  if [[ -z ${PUBLIC_ZONEID+x} || -z ${PUBLIC_DNS+x} || -z ${TTL+x} || -z ${PUBLIC_IPV4+x} ]];
     then
	echo "PUBLIC_ZONEID or PUBLIC_DNS or PUBLIC_IPV4 or TTL are unset";

     else
        echo "Updating Route 53 PUBLIC ZONE record"
	set-dns.bash $PUBLIC_ZONEID $PUBLIC_DNS $TTL $PUBLIC_IPV4 $EC2_REGION;

  fi

}


install_swap_file() {
  if [[ -z ${SWAPFILE_NAME+x} || -z ${SWAPFILE_SIZE+x}  ]];
     then
	echo "SWAPFILE_NAME or SWAPFILE_SIZE are unset";
     else
        echo "creating swapfile"
	dd if=/dev/zero of=$SWAPFILE_NAME bs=1M count=$SWAPFILE_SIZE
	chmod 0600 $SWAPFILE_NAME
	chown root:root $SWAPFILE_NAME
	mkswap $SWAPFILE_NAME
	swapon $SWAPFILE_NAME
	echo "$SWAPFILE_NAME none swap sw 0 0" >> /etc/fstab ;
  fi

}
install_volume() {
  if [[ -z ${VOLUME_ID+x} || -z ${VOLUME_DEVICE+x} || -z ${VOLUME_MOUNT_POINT+x}  ]];
  then
    echo "VOLUME_ID or VOLUME_DEVICE or VOLUME_MOUNT_POINT are unset";
  else
    echo "Attaching EBS volume $VOLUME_ID to EC2 instance $INSTANCE_ID"
    local INSTANCE_ID=$(ec2-metadata | grep instance-id | awk '{print $2}')
    getRegion
    $LOCAL_BINDIR/aws ec2 attach-volume --instance-id "$INSTANCE_ID" --region "$EC2_REGION" --volume-id "$VOLUME_ID" --device "$VOLUME_DEVICE"

    local ATTACHED_STATUS=$(aws ec2 describe-volumes --volume-ids "$VOLUME_ID" --region "$EC2_REGION" --query "Volumes[*].Attachments[*].State" --output text)
    local count=0
    while [[ $ATTACHED_STATUS != "attached" && $count -lt 12 ]]
    do
      sleep 15
      count=$[count+1]
      echo "Volume ID: $VOLUME_ID status: $ATTACHED_STATUS"
      ATTACHED_STATUS=$(aws ec2 describe-volumes --volume-ids "$VOLUME_ID" --region "$EC2_REGION" --query "Volumes[*].Attachments[*].State" --output text)
    done
    echo "Volume ID: $VOLUME_ID status: $ATTACHED_STATUS"
    echo "Mounting EBS volume $VOLUME_ID to mount point $VOLUME_MOUNT_POINT"

    mkdir -p $VOLUME_MOUNT_POINT
    mount  $VOLUME_DEVICE $VOLUME_MOUNT_POINT
    echo "$VOLUME_DEVICE $VOLUME_MOUNT_POINT ext4  rw,exec,relatime,data=ordered  0  2" >> /etc/fstab ;
    echo "export EC2_VOLUME=$VOLUME_MOUNT_POINT" >> /home/ec2-user/.bashrc ;
  fi

}

install_efs() {
  if [[ -z ${EFS_DNS+x} || -z ${EFS_MOUNT_POINT+x}  ]];
     then
	      echo "EFS_DNS or EFS_MOUNT_POINT are unset";
     else
       getRegion
       echo "using /etc/rc.local to configure AWS EFS $EFS_DNS to mount point $EFS_MOUNT_POINT"
       echo "mkdir -p $EFS_MOUNT_POINT" >> /etc/rc.local
       echo "mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $EFS_DNS.efs.$EC2_REGION.amazonaws.com:/ $EFS_MOUNT_POINT" >> /etc/rc.local
       echo "service docker restart" >> /etc/rc.local
       echo "start ecs" >> /etc/rc.local
  fi

}

remove_health_webserver() {
  if [[ -z ${HEALTH_WEBSERVER+x}  ]];
     then
	      echo "HEALTH_WEBSERVER environment variable is NOT set.  Deleting /etc/health-webserver.conf"
        rm /etc/health-webserver.conf;
     else
       	echo "HEALTH_WEBSERVER environment variable is set - move monit config file to /etc/monit.d for health web server."
        mv /etc/health-webserver.conf /etc/monit.d/health-webserver.conf
        monit reload

  fi
}

copy_public_keys() {
  if [[ -z ${SSHD_COPY_KEYS+x}  ]];
     then
	      echo "SSHD_COPY_KEYS environment variable is not set.";
     else
        echo "SSHD_COPY_KEYS environment variable IS set.  Copy public keys."
        $LOCAL_BINDIR/aws s3 cp $S3_BUCKET/authorized_keys /home/ec2-user/.ssh/authorized_keys;
  fi
}
