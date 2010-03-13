#/bin/sh
# karmic 32bit from canonical: ami-bb709dd2
# Chef 0.8.4 client1 Ubuntu 9.10 (ami-258c634c)

instanceid=$(ec2-run-instances   \
  --user-data { "attributes": { "role": "appserver" }  }  \
  --key mikehale                 \
  --instance-type m1.small       \
  ami-258c634c |
  egrep ^INSTANCE | cut -f2)
echo "instanceid=$instanceid"

while host=$(ec2-describe-instances "$instanceid" | 
  egrep ^INSTANCE | cut -f4) && test -z $host; do echo -n .; sleep 1; done
echo host=$host