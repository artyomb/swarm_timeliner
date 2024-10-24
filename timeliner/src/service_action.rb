require 'json'
require 'net/http'
require 'time'

class ServiceAction
  attr_accessor :actor_id, :service_name, :action, :timestamp_nano

  # Constructor: Default and Parametrized
  def initialize(actor_id = "default_actor_id", service_name = "default_service_name", action = "default_action_name", timestamp_nano = nil)
    @actor_id = actor_id
    @service_name = service_name
    @action = action
    @timestamp_nano = timestamp_nano || Time.now.utc.change(hour: 0, min: 0, sec: 0).to_i * 1e9.to_i
  end

  # Method to convert instance to a dictionary-like structure
  def to_dict
    {
      service_name: @service_name,
      action: @action,
      timestamp_nano: @timestamp_nano
    }
  end

  # String representation of the object
  def to_s
    to_dict.to_s
  end

  # Class Method: Parse response from Loki and return list of ServiceAction instances
  def self.get_services_actions_data_by_loki_response(raw_response)
    json_response = JSON.parse(raw_response.body)
    results = json_response.dig('data', 'result') || []
    service_actions_list = []

    results.each do |current_result_dict|
      current_action_dict_from_json = JSON.parse(current_result_dict['values'][0][1])
      current_service_id = current_action_dict_from_json.dig('Actor', 'ID')
      current_service_name = current_action_dict_from_json.dig('Actor', 'Attributes', 'name')
      current_action_name = current_action_dict_from_json['Action']
      current_timestamp_nano = current_action_dict_from_json['timeNano'].to_i

      service_actions_list << ServiceAction.new(current_service_id, current_service_name, current_action_name, current_timestamp_nano)
    end

    service_actions_list
  end
end
