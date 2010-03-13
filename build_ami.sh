#!/bin/sh

key="mikehale"

instanceid=$(ec2-run-instances   \
  --key $key                     \
  --availability-zone us-east-1a \
  --instance-type c1.medium      \
  ami-1515f67c |
  egrep ^INSTANCE | cut -f2)
echo "instanceid=$instanceid"

while host=$(ec2-describe-instances "$instanceid" | 
  egrep ^INSTANCE | cut -f4) && test -z $host; do echo .; sleep 1; done
echo host=$host

sleep 5

rsync -a                                \
  --rsync-path="sudo rsync"             \
  ~/.ec2/{cert,pk}-*.pem run_on_ami.sh ~/.ec2/access_keys  \
  $host:/mnt/

ssh $host /mnt/run_on_ami.sh