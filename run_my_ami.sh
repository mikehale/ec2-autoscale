#!/bin/sh

key="mikehale"
ami="ami-5f2dc236"

instanceid=$(ec2-run-instances   \
  --key $key                     \
  --availability-zone us-east-1a \
  --instance-type m1.small  \
  $ami |
  egrep ^INSTANCE | cut -f2)
echo "instanceid=$instanceid"

while host=$(ec2-describe-instances "$instanceid" | 
  egrep ^INSTANCE | cut -f4) && test -z $host; do echo .; sleep 1; done
echo host=$host

sleep 10

pwd=`pwd`
cd ~/dev/cookbooks
rake build_cookbooks_package
cd $pwd

rsync -ra customize.sh ~/dev/cookbooks/cookbooks.tar.gz $host:
ssh $host
