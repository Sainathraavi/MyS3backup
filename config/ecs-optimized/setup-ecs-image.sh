#!/bin/bash

# this script is for initializing an AWS EC2 ECS optimized AMI with specific
# packages and configuration. This is to be added as ec2 instance User Data when
# first creating a new golden AMI






export LOCAL_BINDIR=/usr/local/bin
export S3_BUCKET=s3://loadcoop/config
export HOME=/home/ec2-user
export MOSH_VERSION=1.2.6
export MONIT_VERSION=5.20.0
# exit script if there is any error
set -e

getRegion() {
  export EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
  export EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

}

install_ssm_agent() {
  getRegion
  cd /tmp
  curl -s -S https://amazon-ssm-$EC2_REGION.s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o amazon-ssm-agent.rpm
  yum install -y amazon-ssm-agent.rpm

}

install_tools() {
  yum -y install autoconf automake gcc gcc-c++ make boost-devel zlib-devel ncurses-devel protobuf-devel openssl-devel
}

remove_tools() {
  yum -y remove autoconf automake gcc gcc-c++ boost-devel zlib-devel ncurses-devel protobuf-devel openssl-devel

}
install_mosh() {

  cd /usr/local/src
  rm -rf mosh-$MOSH_VERSION*
  wget http://mosh.mit.edu/mosh-$MOSH_VERSION.tar.gz
  tar xvf mosh-$MOSH_VERSION.tar.gz
  cd mosh-$MOSH_VERSION
  ./autogen.sh
  ./configure
  make
  make install
  cd /usr/local/src
  rm -rf mosh-$MOSH_VERSION*

}

install_monit() {

  yum -y install pam-devel
  cd /usr/local/src
  rm -rf mosh-$MONIT_VERSION*
  wget https://mmonit.com/monit/dist/monit-$MONIT_VERSION.tar.gz
  tar xvf monit-$MONIT_VERSION.tar.gz
  cd monit-$MONIT_VERSION
  ./configure --prefix /usr
  make
  make install
  cd /usr/local/src
  rm -rf monit-$MONIT_VERSION*
  mkdir /etc/monit.d/

}

install_awslogs_agent() {
  getRegion
  yum install -y awslogs
  echo "[plugins]" > /etc/awslogs/awscli.conf
  echo "cwlogs = cwlogs" >> /etc/awslogs/awscli.conf
  echo "[default]" >> /etc/awslogs/awscli.conf
  echo "region = $EC2_REGION" >> /etc/awslogs/awscli.conf
  service awslogs start
  chkconfig awslogs on
}



yum update -y
yum install -y \
bind-utils \
nfs-utils \
collectd \
bc \
man \
nano \
htop \
curl \
wget \
zip \
unzip \
jq \
python27-pip \
perl \
perl-File-Slurp \
perl-IO-Socket-SSL \
perl-LWP-UserAgent-Determined \
perl-Time-HiRes \
perl-Net-Amazon-EC2 \
perl-DateTime \
perl-DateTime-Format-ISO8601 \
perl-Date-Manip \
tmux \
fail2ban \
dos2unix

# install AWS CLI
pip install --upgrade pip
$LOCAL_BINDIR/pip install awscli
$LOCAL_BINDIR/pip install aws-shell



install_ssm_agent
install_awslogs_agent


install_tools
# rather than use an outdated mosh (mobile ssh) package from the repo, install mosh from source
install_mosh
# use latest monit distribution
install_monit

remove_tools

# install ec2-consistent-snapshot and ec2-expire-snapshots scripts
# these utilities are used when a specific EBS volume has been attached
# to an ec2 instance.
# ec2-consistent-snapshot is used to create a snapshot with optional filesystem
# locking.

# These two popular utilities are docuemmnted at
# https://github.com/alestic/ec2-consistent-snapshot
# https://github.com/alestic/ec2-expire-snapshots
cd $HOME
wget -O ec2-consistent-snapshot.zip \
https://github.com/alestic/ec2-consistent-snapshot/archive/master.zip

wget -O ec2-expire-snapshots.zip \
https://github.com/alestic/ec2-expire-snapshots/archive/master.zip

unzip ec2-consistent-snapshot.zip
unzip ec2-expire-snapshots.zip
cp ec2-consistent-snapshot-master/ec2-consistent-snapshot $LOCAL_BINDIR
cp ec2-expire-snapshots-master/ec2-expire-snapshots $LOCAL_BINDIR
rm -rf $HOME/ec2-*


#
# copy files from s3 bucket to this instance.  these files are configuration files and scripts that
# support the packages installed above.  While not all of the packages installed may not be used,
# they are all required in order to ensure consistent operation.
#
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/.bashrc  $HOME
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/curl-format $HOME
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/ec2-metadata /usr/bin
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/init-ec2-env-vars.sh /usr/bin
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/my-ami-functions.sh /usr/bin
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/set-dns.bash /usr/bin
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/monit.conf /etc/monitrc
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/monit.init.conf /etc/init/monit.conf
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/secure-path.conf /etc/sudoers.d/secure-path

$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/collectd.conf /etc/collectd.conf
#setup health monitoring webserver and monit configuration
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/health-webserver.sh $LOCAL_BINDIR
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/health-webserver.py $LOCAL_BINDIR
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/health-webserver.conf /etc/
$LOCAL_BINDIR/aws s3 cp $S3_BUCKET/ecs-optimized/health-checks.conf /etc/monit.d/

# copy the local yum package manager log to s3 for review or debugging
$LOCAL_BINDIR/aws s3 cp /var/log/yum.log $S3_BUCKET/ecs-optimized/

#  change some file permissions to allow execution
chmod +x /usr/bin/ec2-metadata
chmod +x /usr/bin/init-ec2-env-vars.sh
chmod +x /usr/bin/set-dns.bash
chmod +x $LOCAL_BINDIR/health-webserver.sh
chmod +x $LOCAL_BINDIR/health-webserver.py

# run dos2unix on the above files.
dos2unix $HOME/.bashrc
dos2unix $HOME/curl-format
dos2unix /usr/bin/ec2-metadata
dos2unix /usr/bin/init-ec2-env-vars.sh
dos2unix /usr/bin/my-ami-functions.sh
dos2unix /usr/bin/set-dns.bash
dos2unix /etc/monitrc
dos2unix /etc/init/monit.conf
dos2unix /etc/sudoers.d/secure-path
dos2unix $LOCAL_BINDIR/health-webserver.sh
dos2unix $LOCAL_BINDIR/health-webserver.py

#Somehow wrong file permissions were attached to monit.conf. CHMOD is used below to fix it.
chmod 700 /etc/monitrc

# setup initial monit configuration
initctl reload-configuration
start monit

# setup initial collectd configuration
chkconfig --add collectd
chkconfig collectd on
service collectd start

# setup initial fail2ban configuration
chkconfig --add fail2ban
chkconfig fail2ban on
service fail2ban start

# remove any evidence that we have been here
rm -rf /var/log/*
rm -f $HOME/.bash_history
