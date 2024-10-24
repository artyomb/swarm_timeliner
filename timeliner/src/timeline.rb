require 'net/http'
require 'uri'
require 'json'
require_relative 'service_action'
require_relative 'convertion_for_js'

RESULT_LIST_FOR_CONTAINER_EVENTS = []
QUERY_FOR_CONTAINER_EVENTS = '{job="docker_events"} | json | Type = "container" and Action =~ "start|stop|update|kill"'

RESULT_LIST_FOR_SERVICE_EVENTS = []
QUERY_FOR_SERVICE_EVENTS = '{job="docker_events"} | json | Type = "service" and Action =~ "create|remove|update"'

BASE_LOKI_URL = ENV.fetch('BASE_LOKI_URL', 'http://loki:3100/loki/api/v1')
LIMIT = ENV.fetch('LIMIT', '0').to_i

def update_logs_info
  update_logs_info_for_container_events
  update_logs_info_for_service_events
end

def update_logs_info_for_container_events
  begin
    uri = URI("#{BASE_LOKI_URL}/query_range")
    params = { query: QUERY_FOR_CONTAINER_EVENTS }
    params[:limit] = LIMIT if LIMIT > 0
    uri.query = URI.encode_www_form(params)

    response = Net::HTTP.get_response(uri)
    if response.code.to_i != 200
      puts "Failed to get response from Loki"
      raise response.body
    end

    # Assuming similar function in Ruby version of ServiceContainerActions
    data = JSON.parse(response.body)
    RESULT_LIST_FOR_CONTAINER_EVENTS.replace(ServiceContainerActions::ServiceContainerActionEntry.get_services_containers_data_by_loki_response(data))

  rescue => e
    puts "Error sending request: #{e}"
  end
end

def update_logs_info_for_service_events
  begin
    uri = URI("#{BASE_LOKI_URL}/query_range")
    params = { query: QUERY_FOR_SERVICE_EVENTS }
    params[:limit] = LIMIT if LIMIT > 0
    uri.query = URI.encode_www_form(params)

    response = Net::HTTP.get_response(uri)
    if response.code.to_i != 200
      puts "Failed to get response from Loki"
      raise response.body
    end

    # Assuming similar function in Ruby version of ServiceActions
    data = JSON.parse(response.body)
    RESULT_LIST_FOR_SERVICE_EVENTS.replace(ServiceActions::ServiceAction.get_services_actions_data_by_loki_response(data))

  rescue => e
    puts "Error sending request: #{e}"
  end
end

def get_service_info(service_name)
  update_logs_info
  return RESULT_LIST_FOR_CONTAINER_EVENTS if service_name.nil?

  RESULT_LIST_FOR_CONTAINER_EVENTS.each do |service|
    return service if service.service_name == service_name
  end

  "Your service is not found"
end

def get_backend_timelines_global_info
  update_logs_info

  groups_container, items_container = get_groups_and_items_from_service_container_actions_entries(RESULT_LIST_FOR_CONTAINER_EVENTS)
  groups_service, items_service = get_groups_and_items_from_service_actions_entries(RESULT_LIST_FOR_SERVICE_EVENTS)

  merged_groups, merged_items = merge_groups_and_items_from_services_and_containers_actions(groups_container, items_container, groups_service, items_service)

  result_dict = {
    "groups" => merged_groups.map { |service_name| { "id" => service_name, "content" => service_name } },
    "items" => merged_items.map(&:to_dict)
  }

  result_dict
end
