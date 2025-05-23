# This script installs the Logstash Docker Labels filter plugin.
# It is assumed that the plugin is already built and the .gem file is available in the specified path.
# The script installs the plugin using the Logstash plugin manager.
# Usage: ./install.sh
# Ensure the script is executable
# !/bin/bash
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true
bin/logstash-plugin install /home/test/logstash-filter-docker-labels-0.1.0.gem
logstash -e 'input { stdin { codec => json } } filter { docker_labels { input => "hostname" output => "target_es" } } output { stdout { codec => rubydebug } }'
{"hostname":"whoami.turrican.top"}