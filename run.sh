# !/bin/bash
logstash -e 'input { stdin { codec => json } } filter { docker-labels { input => "hostname" output => "target_es" } } output { stdout { codec => rubydebug } }'