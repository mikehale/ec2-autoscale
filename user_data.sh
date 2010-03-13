#!/bin/bash
set -e -x
chef-solo -j https://s3.amazonaws.com/resources.haletheg/appserver.json -c /etc/chef/solo.rb

#create solo.rb
#create cronjob/start chef-solo as daemon
#cronjob syncs chef cookbooks runs chef-solo

# Chef Client Config File
# Automatically grabs configuration from ohai ec2 metadata.

require 'ohai'
require 'json'

o = Ohai::System.new
o.all_plugins
chef_config = JSON.parse(o[:ec2][:userdata])
if chef_config.kind_of?(Array)
  chef_config = chef_config[o[:ec2][:ami_launch_index]]
end

log_level        :info
log_location     STDOUT
node_name        o[:ec2][:instance_id]

if chef_config.has_key?("attributes")
  File.open("/etc/chef/client-config.json", "w") do |f|
    f.print(JSON.pretty_generate(chef_config["attributes"]))
  end
  json_attribs "/etc/chef/client-config.json"
end

file_cache_path    "/var/chef"
cookbook_path      ["/var/chef/site-cookbooks", "/var/chef/cookbooks"]

Mixlib::Log::Formatter.show_time = true