# encoding: utf-8
require "logstash/filters/base"
require "net/http"
require "uri"
require "json"
require "time"

# This docker-labels filter will read data from an input field,
# query a local HTTP API for Docker services information, and
# write the processed data to an output field.
class LogStash::Filters::DockerLabels < LogStash::Filters::Base
  config_name "docker_labels"

  # Source field to read from
  config :input, :validate => :string, :required => true
  
  # Target field to write to
  config :output, :validate => :string, :required => true

  # API URL to fetch Docker services
  config :api_url, :validate => :string, :default => "http://localhost:5000/docker-services"
  
  # Cache TTL in minutes
  config :cache_ttl, :validate => :number, :default => 5

  # Label names in Docker services
  config :input_label, :validate => :string, :default => "logstash.docker.input"
  config :output_label, :validate => :string, :default => "logstash.docker.output"
  
  # Comparison type for matching input value with label value
  config :comparison_type, :validate => ["equals", "contains", "starts_with", "ends_with", "not_equals", "regex"], :default => "equals"

  public
  def register
    @logger = self.logger
    
    # Initialize cache
    @cache = {}
    @cache_timestamps = {}
  end

  public
  def filter(event)
    input_value = event.get(@input)
    if input_value
      output_value = get_output_for_input(input_value)
      event.set(@output, output_value)
    end

    filter_matched(event)
  end
  
  private
  def get_output_for_input(input_value)
    # Check cache first
    if @cache.has_key?(input_value)
      timestamp = @cache_timestamps[input_value]
      if Time.now - timestamp < @cache_ttl * 60 # TTL in seconds
        return @cache[input_value]
      end
    end
    
    # If not in cache or expired, query the API
    output_value = get_service_label_output(input_value)
    
    # Update cache
    @cache[input_value] = output_value
    @cache_timestamps[input_value] = Time.now
    
    return output_value
  end
  
  private
  def get_service_label_output(input_value)
    begin
      # Query the HTTP API for Docker services
      uri = URI(@api_url)
      response = Net::HTTP.get_response(uri)
      
      if response.is_a?(Net::HTTPSuccess)
        services = JSON.parse(response.body)
        
        # Find service with matching input label
        matching_service = services.find do |service|
          if service["labels"] && service["labels"][@input_label]
            label_value = service["labels"][@input_label]
            compare_values(input_value, label_value)
          else
            false
          end
        end
        
        # If matching service found, get output label value
        if matching_service && matching_service["labels"]
          return matching_service["labels"][@output_label] || nil
        end
      else
        @logger.error("Failed to fetch services from API", :status => response.code)
      end
    rescue => e
      @logger.error("Error querying Docker services API", :exception => e.message, :backtrace => e.backtrace)
    end
    
    # Default return value is null if no match found or error occurred
    return nil
  end
  
  private
  def compare_values(input_value, label_value)
    case @comparison_type
    when "equals"
      label_value == input_value
    when "contains"
      label_value.include?(input_value)
    when "starts_with"
      label_value.start_with?(input_value)
    when "ends_with"
      label_value.end_with?(input_value)
    when "not_equals"
      label_value != input_value
    when "regex"
      !!(label_value =~ Regexp.new(input_value))
    else
      # Default to equals if something unexpected happens
      label_value == input_value
    end
  end
end