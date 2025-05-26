# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/docker_labels"
require "json"

describe LogStash::Filters::DockerLabels do
  let(:plugin) { LogStash::Filters::DockerLabels.new(config) }
  
  describe "Basic configuration" do
    let(:config) do
      {
        "input" => "hostname",
        "output" => "target_es",
        "api_url" => "http://localhost:5000/docker-services",
        "input_label" => "logstash.docker.input",
        "output_label" => "logstash.docker.output"
      }
    end

    before do
      plugin.register
    end

    context "when processing an event with matching input field" do
      let(:event) { LogStash::Event.new("hostname" => "whoami.turrican.top") }
      
      # Mock HTTP API response
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return(
          '[{"id":"988y1stob4ljjeq5wssg7p6q9","name":"whoami_ui","labels":{"com.docker.stack.image":"traefik/whoami","com.docker.stack.namespace":"whoami","logstash.docker.output":"localhost:9200","logstash.docker.input":"whoami.turrican.top","traefik.docker.network":"traefik_swarm","traefik.enable":"true","traefik.http.routers.whoami_ui.rule":"Host(`whoami.turrican.top`)","traefik.http.routers.whoami_ui.service":"whoami_ui","traefik.http.routers.whoami_ui.tls.certresolver":"myresolver","traefik.http.services.whoami_ui.loadbalancer.server.port":"80"}}]'
        )
        
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "sets the output field with the Docker label value" do
        plugin.filter(event)
        expect(event.get("target_es")).to eq("localhost:9200")
      end
    end

    context "when processing an event with no matching container" do
      let(:event) { LogStash::Event.new("hostname" => "non-existent-host") }
      
      # Mock HTTP API response
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return('[]')
        
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "sets the output field to nil" do
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end

    context "when input field is missing" do
      let(:event) { LogStash::Event.new("some_other_field" => "value") }
      
      it "doesn't modify the event" do
        original_event = event.clone
        plugin.filter(event)
        # The output field should not be set
        expect(event.get("target_es")).to be_nil
        # The rest of the event should be unchanged
        expect(event.to_hash.reject{|k,v| k == "@timestamp"}).to eq(original_event.to_hash.reject{|k,v| k == "@timestamp"})
      end
    end
    
    context "when API call fails" do
      let(:event) { LogStash::Event.new("hostname" => "whoami.turrican.top") }
      
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return(500)
        
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "sets the output field to nil" do
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
  end
  
  describe "Cache functionality" do
    let(:config) do
      {
        "input" => "hostname",
        "output" => "target_es",
        "cache_ttl" => 5
      }
    end

    before do
      plugin.register
    end

    context "when processing multiple events with same input value" do
      let(:event1) { LogStash::Event.new("hostname" => "cache-test") }
      let(:event2) { LogStash::Event.new("hostname" => "cache-test") }
      
      it "calls API only once" do
        # Mock the API response
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return(
          '[{"id":"test","name":"test_service","labels":{"logstash.docker.input":"cache-test","logstash.docker.output":"cached-value"}}]'
        )
        
        # Expect only one call to get_response
        expect(Net::HTTP).to receive(:get_response).once.and_return(mock_response)
        
        plugin.filter(event1)
        plugin.filter(event2)
        
        expect(event1.get("target_es")).to eq("cached-value")
        expect(event2.get("target_es")).to eq("cached-value")
      end
    end
  end
  
  describe "Comparison types" do
    let(:mock_services_json) do
      '[
        {"id":"service1","name":"service1","labels":{"logstash.docker.input":"exact-match","logstash.docker.output":"exact-value"}},
        {"id":"service2","name":"service2","labels":{"logstash.docker.input":"this-contains-substring-here","logstash.docker.output":"contains-value"}},
        {"id":"service3","name":"service3","labels":{"logstash.docker.input":"starts-with-prefix","logstash.docker.output":"starts-with-value"}},
        {"id":"service4","name":"service4","labels":{"logstash.docker.input":"suffix-ends-with","logstash.docker.output":"ends-with-value"}},
        {"id":"service5","name":"service5","labels":{"logstash.docker.input":"not-equal-test","logstash.docker.output":"not-equal-value"}},
        {"id":"service6","name":"service6","labels":{"logstash.docker.input":"regex-test-123","logstash.docker.output":"regex-value"}}
      ]'
    end
    
    before do
      # Setup mock response for all tests in this describe block
      mock_response = double("response")
      allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(mock_response).to receive(:body).and_return(mock_services_json)
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
    end

    context "with 'equals' comparison (default)" do
      let(:config) do
        {
          "input" => "hostname",
          "output" => "target_es",
          "comparison_type" => "equals"
        }
      end
      
      before do
        plugin.register
      end
      
      it "matches exact values" do
        event = LogStash::Event.new("hostname" => "exact-match")
        plugin.filter(event)
        expect(event.get("target_es")).to eq("exact-value")
      end
      
      it "doesn't match partial values" do
        event = LogStash::Event.new("hostname" => "exact")
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
    
    context "with 'contains' comparison" do
      let(:config) do
        {
          "input" => "hostname",
          "output" => "target_es",
          "comparison_type" => "contains"
        }
      end
      
      before do
        plugin.register
      end
      
      it "matches when label contains the input value" do
        event = LogStash::Event.new("hostname" => "substring")
        plugin.filter(event)
        expect(event.get("target_es")).to eq("contains-value")
      end
      
      it "doesn't match when label doesn't contain the input value" do
        event = LogStash::Event.new("hostname" => "missing-text")
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
    
    context "with 'starts_with' comparison" do
      let(:config) do
        {
          "input" => "hostname",
          "output" => "target_es",
          "comparison_type" => "starts_with"
        }
      end
      
      before do
        plugin.register
      end
      
      it "matches when label starts with the input value" do
        event = LogStash::Event.new("hostname" => "starts-with")
        plugin.filter(event)
        expect(event.get("target_es")).to eq("starts-with-value")
      end
      
      it "doesn't match when label doesn't start with the input value" do
        event = LogStash::Event.new("hostname" => "with-prefix")
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
    
    context "with 'ends_with' comparison" do
      let(:config) do
        {
          "input" => "hostname",
          "output" => "target_es",
          "comparison_type" => "ends_with"
        }
      end
      
      before do
        plugin.register
      end
      
      it "matches when label ends with the input value" do
        event = LogStash::Event.new("hostname" => "ends-with")
        plugin.filter(event)
        expect(event.get("target_es")).to eq("ends-with-value")
      end
      
      it "doesn't match when label doesn't end with the input value" do
        event = LogStash::Event.new("hostname" => "suffix")
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
    
    context "with 'not_equals' comparison" do
      let(:config) do
        {
          "input" => "hostname",
          "output" => "target_es",
          "comparison_type" => "not_equals"
        }
      end
      
      before do
        plugin.register
      end
      
      it "matches when label is not equal to input value" do
        event = LogStash::Event.new("hostname" => "different-value")
        plugin.filter(event)
        expect(event.get("target_es")).to eq("not-equal-value")
      end
      
      it "doesn't match when label equals the input value" do
        event = LogStash::Event.new("hostname" => "not-equal-test")
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
    
    context "with 'regex' comparison" do
      let(:config) do
        {
          "input" => "hostname",
          "output" => "target_es",
          "comparison_type" => "regex"
        }
      end
      
      before do
        plugin.register
      end
      
      it "matches when label matches the regex pattern" do
        event = LogStash::Event.new("hostname" => "regex-test-\\d+")
        plugin.filter(event)
        expect(event.get("target_es")).to eq("regex-value")
      end
      
      it "doesn't match when label doesn't match the regex pattern" do
        event = LogStash::Event.new("hostname" => "regex-[a-z]+")
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
  end
  
  describe "Exception handling" do
    let(:config) do
      {
        "input" => "hostname",
        "output" => "target_es"
      }
    end
    
    before do
      plugin.register
    end
    
    context "when HTTP request raises an exception" do
      let(:event) { LogStash::Event.new("hostname" => "test-host") }
      
      before do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("Connection failed"))
      end
      
      it "logs the error and sets the output field to nil" do
        expect(plugin.logger).to receive(:error).with("Error querying Docker services API", hash_including(:exception => "Connection failed"))
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
    
    context "when JSON parsing fails" do
      let(:event) { LogStash::Event.new("hostname" => "test-host") }
      
      before do
        mock_response = double("response")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return("invalid json")
        allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      end
      
      it "logs the error and sets the output field to nil" do
        expect(plugin.logger).to receive(:error).with("Error querying Docker services API", hash_including(:exception => /unexpected token/i))
        plugin.filter(event)
        expect(event.get("target_es")).to be_nil
      end
    end
  end
end