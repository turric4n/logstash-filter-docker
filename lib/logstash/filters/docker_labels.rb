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
  
  # Enable or disable caching
  config :use_cache, :validate => :boolean, :default => true
  
  # Cache TTL in minutes for individual lookups
  config :cache_ttl, :validate => :number, :default => 5
  
  # Services cache TTL in minutes
  config :services_cache_ttl, :validate => :number, :default => 10

  # Label names in Docker services
  config :input_label, :validate => :string, :default => "logstash.docker.input"
  config :output_label, :validate => :string, :default => "logstash.docker.output"

  # Comparison type for matching label keys with the input_label pattern
  config :input_label_comparison_type, :validate => ["equals", "contains", "starts_with", "ends_with", "not_equals", "regex"], :default => "equals"
  
  # Comparison type for matching field value with label value
  config :input_comparison_type, :validate => ["equals", "contains", "starts_with", "ends_with", "not_equals", "regex"], :default => "equals"
  
  # Fallback output value to use when no match is found
  config :fallback_output, :validate => :string, :default => nil
  
  # Enable debug output
  config :debug, :validate => :boolean, :default => false

  # Fixed input-output rules that have priority over Docker service lookups
  config :fixed_rules, :validate => :array, :default => []

  public
  def register
    @logger = self.logger
    
    # Validate fixed_rules structure
    @fixed_rules.each_with_index do |rule, index|
      unless rule.is_a?(Hash) && rule.has_key?("input") && rule.has_key?("output")
        raise LogStash::ConfigurationError, "Fixed rule at index #{index} must be a hash with 'input' and 'output' keys"
      end
      
      if rule.has_key?("comparison_type") && !["equals", "contains", "starts_with", "ends_with", "not_equals", "regex"].include?(rule["comparison_type"])
        raise LogStash::ConfigurationError, "Invalid comparison_type '#{rule["comparison_type"]}' in fixed rule at index #{index}"
      end
    end

    # Initialize value cache
    @cache = {}
    @cache_timestamps = {}
    
    # Initialize services cache
    @services_cache = nil
    @services_cache_timestamp = nil
    
    if @debug
      @logger.info("Docker Labels filter initialized with debug mode", 
        :input => @input,
        :output => @output,
        :input_label => @input_label,
        :output_label => @output_label,
        :input_label_comparison_type => @input_label_comparison_type,
        :input_comparison_type => @input_comparison_type,
        :use_cache => @use_cache)
      
      if !@use_cache
        @logger.info("Caching is disabled")
      end
    end
  end

  public
  def filter(event)
    input_value = event.get(@input)
    if input_value
      if @debug
        @logger.info("Processing input value", :input_field => @input, :input_value => input_value)
      end
      
      output_value = get_output_for_input(input_value)
      
      if @debug
        @logger.info("Setting output value", :output_field => @output, :output_value => output_value)
      end
      
      event.set(@output, output_value)
    elsif @debug
      @logger.info("Input field not found in event", :input_field => @input)
    end

    filter_matched(event)
  end
  
  private
  def get_output_for_input(input_value)
    # Check fixed rules first (highest priority)
    if !@fixed_rules.empty?
      matching_rule = @fixed_rules.find do |rule|
        if rule.is_a?(Hash) && rule.has_key?("input") && rule.has_key?("output")
          # Compare based on the rule's comparison type if specified
          comparison_type = rule["comparison_type"] || @input_comparison_type
          compare_values(input_value, rule["input"], comparison_type)
        else
          false
        end
      end
      
      if matching_rule
        if @debug
          @logger.info("Fixed rule match found", 
            :input_value => input_value, 
            :rule => matching_rule,
            :output => matching_rule["output"])
        end
        return matching_rule["output"]
      elsif @debug
        @logger.info("No matching fixed rule found", :input_value => input_value)
      end
    end
    
    # Check value cache first (if caching is enabled)
    if @use_cache && @cache.has_key?(input_value)
      timestamp = @cache_timestamps[input_value]
      if Time.now - timestamp < @cache_ttl * 60 # TTL in seconds
        if @debug
          @logger.info("Cache hit", :input_value => input_value, :output_value => @cache[input_value])
        end
        return @cache[input_value]
      elsif @debug
        @logger.info("Cache expired", :input_value => input_value, :age => (Time.now - timestamp)/60.0, :ttl => @cache_ttl)
      end
    elsif @debug
      if !@use_cache
        @logger.info("Cache lookup skipped (caching disabled)", :input_value => input_value)
      else
        @logger.info("Cache miss", :input_value => input_value)
      end
    end
    
    # If not in cache, cache disabled, or expired, find in services
    output_value = find_service_output(input_value)
    
    # Use fallback if no match found
    if output_value.nil?
      if @debug && !@fallback_output.nil?
        @logger.info("Using fallback output", :fallback_value => @fallback_output)
      end
      output_value = @fallback_output
    end
    
    # Update cache (if caching is enabled)
    if @use_cache
      @cache[input_value] = output_value
      @cache_timestamps[input_value] = Time.now
      
      if @debug
        @logger.info("Updated cache", :input_value => input_value, :output_value => output_value)
      end
    elsif @debug
      @logger.info("Skipped cache update (caching disabled)", :input_value => input_value)
    end
    
    return output_value
  end
  
  private
  def find_service_output(input_value)
    # Get the services (either from cache or from API)
    services = get_services()
    
    if services.nil?
      @logger.warn("No services available") if @debug
      return nil
    end
    
    if @debug
      @logger.info("Searching through services", :service_count => services.length)
    end
    
    # Find service with matching input label
    matching_service = nil
    
    services.each do |service|
      next unless service["labels"]
      
      if @debug
        @logger.info("Checking service", 
          :service_name => service["name"], 
          :label_pattern => @input_label,
          :comparison_type => @input_label_comparison_type)
      end
      
      # Find matching label key
      matching_key = nil
      
      service["labels"].keys.each do |key|
        match = false
        
        if @input_label_comparison_type == "regex"
          begin
            # Convert escaped dots from \. to \.
            fixed_pattern = @input_label.gsub(/\\+\./, '\.')
            
            if @debug
              @logger.info("Trying regex match", 
                :key => key, 
                :pattern => fixed_pattern)
            end
            
            match = !!(key =~ Regexp.new(fixed_pattern))
            
            if @debug && match
              @logger.info("Regex match found!", :key => key, :pattern => fixed_pattern)
            end
          rescue => e
            @logger.error("Regex error", :error => e.message, :pattern => @input_label)
            match = false
          end
        elsif @input_label_comparison_type == "contains"
          # For contains, convert escaped pattern to literal
          plain_pattern = @input_label.gsub(/\\\./, '.')
          match = key.include?(plain_pattern)
        else
          # Other comparison types
          match = compare_values(key, @input_label, @input_label_comparison_type)
        end
        
        if match
          matching_key = key
          break
        end
      end
      
      # If we found a matching key
      if matching_key
        label_value = service["labels"][matching_key]
        
        if @debug
          @logger.info("Found matching label", 
            :service_name => service["name"],
            :label_key => matching_key,
            :label_value => label_value)
        end
        
        # Check if the input value matches the label value
        value_match = compare_values(input_value, label_value, @input_comparison_type)
        
        if value_match
          matching_service = service
          break
        end
      end
    end
    
    # Rest of the method remains the same...
    
    if matching_service && matching_service["labels"]
      return matching_service["labels"][@output_label] || nil
    end
    
    return nil
  end
  
  private
  def get_services
    # Check if services cache is valid (if caching is enabled)
    if @use_cache && @services_cache && @services_cache_timestamp
      cache_age = Time.now - @services_cache_timestamp
      if cache_age < @services_cache_ttl * 60 # TTL in seconds
        if @debug
          @logger.info("Using cached services list", 
            :cache_age => (cache_age/60.0).round(2),
            :ttl => @services_cache_ttl,
            :services_count => @services_cache.length)
        end
        return @services_cache
      elsif @debug
        @logger.info("Services cache expired", 
          :cache_age => (cache_age/60.0).round(2), 
          :ttl => @services_cache_ttl)
      end
    elsif @debug && !@use_cache
      @logger.info("Services cache lookup skipped (caching disabled)")
    end
    
    # Cache disabled, expired or not set, query the API
    begin
      if @debug
        @logger.info("Fetching services from API", :url => @api_url)
      end
      
      # Query the HTTP API for Docker services
      uri = URI(@api_url)
      response = Net::HTTP.get_response(uri)
      
      if response.is_a?(Net::HTTPSuccess)
        # Parse services
        services = JSON.parse(response.body)
        
        # Cache the services (if caching is enabled)
        if @use_cache
          @services_cache = services
          @services_cache_timestamp = Time.now
          
          if @debug
            @logger.info("Services cached", :count => services.length)
          end
        elsif @debug
          @logger.info("Services not cached (caching disabled)", :count => services.length)
        end
        
        if @debug
          @logger.info("Services fetched successfully", :count => services.length)
        end
        
        return services
      else
        @logger.error("Failed to fetch services from API", :status => response.code)
      end
    rescue => e
      @logger.error("Error querying Docker services API", :exception => e.message, :backtrace => e.backtrace)
    end
    
    # Return nil on failure, which will lead to returning nil for the output value
    return nil
  end
  
  private
  def compare_values(input_value, label_value, comparison_type = nil)
    # Use provided comparison_type or fall back to default input_comparison_type (was comparison_type)
    comparison_type ||= @input_comparison_type
    
    result = false
    
    case comparison_type
    when "equals"
      result = (label_value == input_value)
      if @debug
        @logger.info("Equals comparison", :label => label_value, :input => input_value, :result => result)
      end
      
    when "contains"
      result = label_value.include?(input_value)
      if @debug
        @logger.info("Contains comparison", :label => label_value, :input => input_value, :result => result)
      end
      
    when "starts_with"
      result = label_value.start_with?(input_value)
      if @debug
        @logger.info("Starts with comparison", :label => label_value, :input => input_value, :result => result)
      end
      
    when "ends_with"
      result = label_value.end_with?(input_value)
      if @debug
        @logger.info("Ends with comparison", :label => label_value, :input => input_value, :result => result)
      end
      
    when "not_equals"
      result = (label_value != input_value)
      if @debug
        @logger.info("Not equals comparison", :label => label_value, :input => input_value, :result => result)
      end
      
    when "regex"
      begin
        result = !!(label_value =~ Regexp.new(input_value))
        if @debug
          @logger.info("Regex comparison", :label => label_value, :pattern => input_value, :result => result)
        end
      rescue RegexpError => e
        @logger.error("Invalid regex pattern", :pattern => input_value, :error => e.message)
        result = false
      end
      
    else
      # Default to equals if something unexpected happens
      result = (label_value == input_value)
      if @debug
        @logger.info("Default equals comparison (unknown type: #{comparison_type})", 
          :label => label_value, 
          :input => input_value, 
          :result => result)
      end
    end
    
    return result
  end
end