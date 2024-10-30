require 'net/http'
require 'uri'
require 'json'

CONTAINER_START_ACTIONS = %w[create exec_create exec_start start]

CONTAINER_STOP_ACTIONS = %w[destroy die kill stop]


TRACKED_CONTAINER_EVENTS = %w[attach commit copy create destroy detach die exec_create
                              exec_detach exec_die exec_start export health_status kill
                              oom pause rename resize restart start stop top unpause update]

TRACKED_SERVICE_EVENTS = %w[create remove update]

QUERY_FOR_CONTAINER_EVENTS = '{job="docker_events"} | json | Type = "container" and Action =~ "' + TRACKED_CONTAINER_EVENTS.join('|') + '"'
QUERY_FOR_SERVICE_EVENTS = '{job="docker_events"} | json | Type = "service" and Action =~ "' + TRACKED_SERVICE_EVENTS.join('|') + '"'
COMBINED_QUERY = '{job="docker_events"} | json | ((Type = "container" and Action =~ "' +
                  TRACKED_CONTAINER_EVENTS.join('|') + '") or (Type = "service" and Action =~ "' +
                  TRACKED_SERVICE_EVENTS.join('|') + '"))'

BASE_LOKI_URL = ENV.fetch('BASE_LOKI_URL', 'http://loki:3100/loki/api/v1')

def get_status_event(event)
  statuses = []
  case event[:ext_code]
  when nil
    statuses << 'neutral'
  when 0
    statuses << 'ok'
  else
    statuses << 'error'
  end
end

def get_status_cont(start, end_val, latest_start)
  statuses = []
  if end_val.nil? || (!latest_start.nil? && end_val < latest_start)
    statuses << 'ok'
  else
    statuses << 'neutral'
  end
  if start.nil?
    statuses << 'start_unknown'
  end
  statuses
end


def get_timeline_data(data)
  limit = begin
             data[:limit].to_i
           rescue
             -1
           end || -1
  since = data[:since]
  collect_health_checks = data[:collect_health_checks]
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
  params = { query: COMBINED_QUERY }
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
    svc_name = rec[:Actor][:Attributes][:'com.docker.swarm.service.name'] || 'default_service'
    cid = rec[:Actor][:ID]
    action = rec[:Action]
    timestamp = rec[:time]
    ext_code = rec[:Actor][:Attributes][:exitCode]
    services[svc_name] ||= { containers: {}, events: [] }
    if rec[:Type] == 'container'
      services[svc_name][:containers][cid] ||= { start: nil, end: nil, latest_start: nil, events: [] }
      services[svc_name][:containers][cid][:events] << { action: action, timestamp: timestamp, ext_code: ext_code }
      services[svc_name][:containers][cid][:start] = timestamp if ((CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:start] == nil) || (services[svc_name][:containers][cid][:start] > timestamp)))
      services[svc_name][:containers][cid][:latest_start] = timestamp if ((CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:latest_start] == nil) || (services[svc_name][:containers][cid][:latest_start] < timestamp)))
      services[svc_name][:containers][cid][:end] = timestamp if ((CONTAINER_STOP_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:end] == nil) || (services[svc_name][:containers][cid][:end] < timestamp)))
    end
    if rec[:Type] == 'service'
      puts "svc_name: #{svc_name}, action: #{action}, timestamp: #{timestamp}"
      services[svc_name][:events] << { action: action, timestamp: timestamp, ext_code: ext_code }
    end
  end
  puts "services events registered in dict = #{services.keys.flat_map { |svc_name| services[svc_name][:events].flat_map {|event| { id: svc_name, content: event[:action], ext_code: event[:ext_code], type: 'point', groupId: svc_name, start: event[:timestamp], statuses: get_status_event(event) } } }}"
  results = {
    groups: services.map { |n, v| { id: n, name: n, type: 'service', containers: v[:containers].keys } }  +
      services.keys.flat_map { |svc_name| services[svc_name][:containers].keys.flat_map { |cid| { id: cid, name: cid, type: 'container' } } },
    items: services.keys.flat_map { |svc_name| services[svc_name][:containers].flat_map {|cid, cont| cont[:events].map {|event| { id: cid + " " + event[:action] + " " + event[:timestamp].to_s, content: event[:action], type: 'point', groupId: cid, start: event[:timestamp], ext_code: event[:ext_code], statuses: get_status_event(event) } } } } +    # container_events
      services.keys.flat_map { |svc_name| services[svc_name][:events].flat_map {|event| { id: svc_name + " " + event[:action] + " " + event[:timestamp].to_s, content: event[:action], ext_code: event[:ext_code], type: 'point', groupId: svc_name, start: event[:timestamp], statuses: get_status_event(event) } } } +    # service_events
      services.keys.flat_map{ |svc_name| services[svc_name][:containers].flat_map { |cid, cont| { id: cid, content: "Container", type: 'range', myType: 'canBeExploredById', groupId: cid, start: cont[:start].nil? ? default_start_time : cont[:start] , end: cont[:end].nil? ? default_end_time : cont[:end], statuses: get_status_cont(cont[:start], cont[:end], cont[:latest_start]) } } }   # containers
  }
  results
end
