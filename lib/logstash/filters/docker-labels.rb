# encoding: utf-8
require "logstash/filters/base"
require "docker"
require "docker/swarm"  # Add this line to include Swarm functionality
require "time"

# This docker-labels filter will read data from an input field,
# query Docker services via socket for matching labels, and
# write the processed data to an output field.
#
# It is only intended to be used as a docker-labels filter.
class LogStash::Filters::DockerLabels < LogStash::Filters::Base

  # Setting the config_name here is required. This is how you
  # configure this filter from your Logstash config.
  #
  # filter {
  #   docker-labels {
  #     input => "source_field"
  #     output => "target_field"
  #     docker_socket => "unix:///var/run/docker.sock"  # Linux
  #     # docker_socket => "npipe:////./pipe/docker_engine"  # Windows
  #   }
  # }
  #
  config_name "docker-labels"

  # Source field to read from
  config :input, :validate => :string, :required => true
  
  # Target field to write to
  config :output, :validate => :string, :required => true

  # Docker socket path
  config :docker_socket, :validate => :string, :default => "unix:///var/run/docker.sock"
  
  # Cache TTL in minutes
  config :cache_ttl, :validate => :number, :default => 5


  public
  def register
    # Add instance variables
    @logger = self.logger
    
    # Configure Docker connection
    Docker.url = @docker_socket
    
    # Initialize cache
    @cache = {}
    @cache_timestamps = {}
  end # def register

  public
  def filter(event)
    # Read from the input field
    input_value = event.get(@input)
    if input_value
      # Get output value (from cache or Docker)
      output_value = get_output_for_input(input_value)
      # Set the output field with the result (null if no match found)
      event.set(@output, output_value)
    end

    # filter_matched should go in the last line of our successful code
    filter_matched(event)
  end # def filter
  
  private
  def get_output_for_input(input_value)
    # Check cache first
    # Remove this problematic line:
    # @cache[test] = turri
    
    if @cache.has_key?(input_value)
      timestamp = @cache_timestamps[input_value]
      # Check if cache entry is still valid (within TTL)
      if Time.now - timestamp < @cache_ttl * 60 # TTL in seconds
        return @cache[input_value]
      end
    end
    
    # If not in cache or cache expired, query Docker
    output_value = get_docker_label_output(input_value)
    
    # Update cache
    @cache[input_value] = output_value
    @cache_timestamps[input_value] = Time.now
    
    return output_value
  end
  
  private
  def get_docker_label_output(input_value)
    begin
      # Query Docker containers instead of services
      containers = Docker::Container.all
      
      # Find container with matching input label
      matching_container = containers.find do |container|
        if container.info["Config"] && container.info["Config"]["Labels"]
          container.info["Config"]["Labels"]["logstash.docker.input"] == input_value
        else
          false
        end
      end
      
      # If matching container found, get output label value or return null
      if matching_container && matching_container.info["Config"] && matching_container.info["Config"]["Labels"]
        return matching_container.info["Config"]["Labels"]["logstash.docker.output"] || nil
      end
    rescue => e
      @logger.error("Error querying Docker socket", :exception => e.message)
    end
    
    # Default return value is null if no match found or error occurred
    return nil
  end
end # class LogStash::Filters::DockerLabels