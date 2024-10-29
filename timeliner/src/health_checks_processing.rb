require 'net/http'
require 'uri'
require 'json'

CONTAINER_START_ACTIONS = %w[create exec_create exec_start start]

CONTAINER_STOP_ACTIONS = %w[destroy die exec_die kill stop]

HEALTH_CHECK_EVENTS = %w[exec_start exec_create exec_die]

TRACKED_CONTAINER_EVENTS = CONTAINER_START_ACTIONS + CONTAINER_STOP_ACTIONS + HEALTH_CHECK_EVENTS

TRACKED_SERVICE_EVENTS = %w[create remove update]

QUERY_FOR_CONTAINER_EVENTS = '{job="docker_events"} | json | Type = "container" and Action =~ "' + TRACKED_CONTAINER_EVENTS.join('|') + '"'
QUERY_FOR_SERVICE_EVENTS = '{job="docker_events"} | json | Type = "service" and Action =~ "' + TRACKED_SERVICE_EVENTS.join('|') + '"'
COMBINED_QUERY = '{job="docker_events"} | json | ((Type = "container" and Action =~ "' +
  TRACKED_CONTAINER_EVENTS.join('|') + '") or (Type = "service" and Action =~ "' +
  TRACKED_SERVICE_EVENTS.join('|') + '"))'

BASE_LOKI_URL = ENV.fetch('BASE_LOKI_URL', 'http://loki:3100/loki/api/v1')

def get_status_health_check(health_check)
  nil
end

def get_status_cont(start, end_val, latest_start)
  statuses = []
  if end_val.nil? || latest_start.nil? || end_val < latest_start
    statuses << 'ok'
  else
    statuses << 'neutral'
  end
  if start.nil?
    statuses << 'start_unknown'
  end
  statuses
end


def get_health_checks(data)
  limit = begin
            data[:limit].to_i
          rescue
            -1
          end || -1
  since = data[:since]
  default_end_time = Time.now.to_i
  default_start_time = begin
                         value, unit = since.match(/^(\d+)?([mhd]|all)$/)&.captures || [nil, nil]
                         value = value&.to_i || 1
                         case unit
                         when 'm'
                           default_end_time - (value * 60)
                         when 'h'
                           default_end_time - (value * 60 * 60)
                         when 'd'
                           default_end_time - (value * 24 * 60 * 60)
                         when 'all'
                           default_end_time - (365 * 24 * 60 * 60)
                         else
                           default_end_time - (30 * 60)
                         end
                       end
  uri = URI("#{BASE_LOKI_URL}/query_range")
  params = { query: QUERY_FOR_CONTAINER_EVENTS }
  params[:limit] = limit if limit > 0
  params[:since] = since if since != 'all'
  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  if response.code.to_i != 200
    puts 'Failed to get response from Loki'
    raise response.body
  end

  data = JSON.parse response.body, symbolize_names: true
  data = data[:data][:result].map { JSON.parse _1[:values][0][1], symbolize_names: true }
  services = {}
  data.each do |rec|
    svc_name = rec[:Actor][:Attributes][:'com.docker.swarm.service.name']
    cid = rec[:Actor][:ID]
    action = rec[:Action]
    timestamp = rec[:time]
    ext_code = rec[:Actor][:Attributes][:exitCode]
    hc_id = rec[:Actor][:Attributes][:execID]
    services[svc_name] ||= { containers: {} }
    services[svc_name][:containers][cid] ||= { start: nil, end: nil, latest_start: nil, health_checks: {} }
    services[svc_name][:containers][cid][:start] = timestamp if (CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:start] == nil) || (services[svc_name][:containers][cid][:start] > timestamp))
    services[svc_name][:containers][cid][:latest_start] = timestamp if (CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:latest_start] == nil) || (services[svc_name][:containers][cid][:latest_start] < timestamp))
    services[svc_name][:containers][cid][:end] = timestamp if (CONTAINER_STOP_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:end] == nil) || (services[svc_name][:containers][cid][:end] < timestamp))
    if HEALTH_CHECK_EVENTS.any? { |event| action.include?(event)}
      services[svc_name][:containers][cid][:health_checks][hc_id] ||= { hc_id: hc_id, start_hc: nil, end_hc: nil, ext_code: nil }
      services[svc_name][:containers][cid][:health_checks][hc_id][:start_hc] = timestamp if services[svc_name][:containers][cid][:health_checks][hc_id][:start_hc].nil? || timestamp < services[svc_name][:containers][cid][:health_checks][hc_id][:start_hc]
      services[svc_name][:containers][cid][:health_checks][hc_id][:end_hc] = timestamp if services[svc_name][:containers][cid][:health_checks][hc_id][:end_hc].nil? || timestamp < services[svc_name][:containers][cid][:health_checks][hc_id][:end_hc]
      services[svc_name][:containers][cid][:health_checks][hc_id][:ext_code] = ext_code if !ext_code.nil? && services[svc_name][:containers][cid][:health_checks][hc_id][:ext_code].nil? && action.include?('exec_die')
    end
  end
  # collected_values = services.keys.flat_map { |svc_name| services[svc_name][:containers].keys.map { |cid| { id: cid, name: cid, type: 'container'} } }
  # serviceev_items = services.keys.flat_map { |svc_name| services[svc_name][:events].map {|event| {id: svc_name, content: event[:action], ext_code: event[:ext_code], type: 'point', groupId: svc_name, start: event[:timestamp]}}}
  # containerev_items = services.keys.flat_map{ |svc_name| services[svc_name][:containers].flat_map { |cid, cont| cont[:events].map {|event| {id: cid + event[:action] + event[:timestamp].to_s, content: event[:action], type: 'point', groupId: cid, start: event[:timestamp] } } } }
  # container_items = services.keys.flat_map{ |svc_name| services[svc_name][:containers].flat_map { |cid, cont| { id: cid, content: "Container " + cid, type: 'range', groupId: cid, start: cont[:start], end: cont[:end] } } }
  results = {
    groups: services.map { |n, v| { id: n, name: n, type: 'service', containers: v[:containers].keys } }  +
      services.keys.flat_map { |svc_name| services[svc_name][:containers].keys.flat_map { |cid| { id: cid, name: cid, type: 'container' } } },
    items: services.keys.flat_map { |svc_name| services[svc_name][:containers].flat_map {|cid, cont| cont[:events].map {|event| { id: cid + " " + event[:action] + " " + event[:timestamp].to_s, content: event[:action], type: 'point', groupId: cid, start: event[:timestamp], ext_code: event[:ext_code], statuses: get_status_event(event) } } } } +    # container_events
      services.keys.flat_map { |svc_name| services[svc_name][:events].flat_map {|event| { id: svc_name, content: event[:action], ext_code: event[:ext_code], type: 'point', groupId: svc_name, start: event[:timestamp], ext_code: event[:ext_code], statuses: get_status_event(event) } } } +    # service_events
      services.keys.flat_map{ |svc_name| services[svc_name][:containers].flat_map { |cid, cont| { id: cid, content: "Container", type: 'range', groupId: cid, start: cont[:start].nil? ? default_start_time : cont[:start] , end: cont[:end].nil? ? default_end_time : cont[:end], statuses: get_status_cont(cont[:start], cont[:end], cont[:latest_start]) } } }   # containers
  }
  results
end
# Iterating through all service keys, for each key get [:containers].keys, iterating through them and extract dict with {field: val, field2 :val2} end collect this dicts with values into one array