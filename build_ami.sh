#!/bin/sh

key="mikehale"

if [ $1 = 'bigiron' ]; then
  ami="ami-ab15f6c2"
  instancetype="m1.large"
else
  ami="ami-1515f67c"
  instancetype="c1.medium"
fi

instanceid=$(ec2-run-instances   \
  --key $key                     \
  --availability-zone us-east-1a \
  --instance-type $instancetype  \
  $ami |
  egrep ^INSTANCE | cut -f2)
echo "instanceid=$instanceid"


while host=$(ec2-describe-instances "$instanceid" | 
  egrep ^INSTANCE | cut -f4) && test -z $host; do echo .; sleep 1; done
echo host=$host

sleep 10

rsync -a                                \
  --rsync-path="sudo rsync"             \
  ~/.ec2/{cert,pk}-*.pem run_on_ami.sh ~/.ec2/access_keys  \
  $host:/mnt/

# ssh $host /mnt/run_on_ami.sh
ssh $host

#terminate instance
# ec2-terminate-instances $instanceid