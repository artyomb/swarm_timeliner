require 'net/http'
require 'uri'
require 'json'
require_relative 'loki.rb'
require_relative 'queries_generation.rb'
require_relative 'status_analyzer.rb'

CONTAINER_START_ACTIONS = %w[create start]
CONTAINER_STOP_ACTIONS = %w[destroy die kill stop]

HEALTH_CHECK_EVENTS = %w[exec_start exec_create exec_die]

IGNORE_HEALTH_CHECK_EVENTS = '{job="docker_events"} | json | Type = "container" | Action !~ "exec.*"'

BASE_LOKI_HOST = ENV.fetch('BASE_LOKI_HOST', 'loki')
BASE_LOKI_PORT = ENV.fetch('BASE_LOKI_PORT', '3100').to_i

# BASE_LOKI_URL = ENV.fetch('BASE_LOKI_URL', 'http://loki:3100/loki/api/v1')

LOKI_BATCH_SIZE = ENV.fetch('LOKI_BATCH_SIZE', 1000).to_i

LOKI_CLIENT = LokiClient.new(BASE_LOKI_HOST, port: BASE_LOKI_PORT, **{limit: LOKI_BATCH_SIZE, logger: Logger.new($stdout)})
QUERY_GENERATOR = QueriesGenerator.new(ENV.fetch('TARGET_"JOB', 'docker_events'))

def get_timeline_data(data)
  since = data[:since]
  collect_health_checks = data[:collect_health_checks]
  load_source_jsons = data[:load_source_jsons]
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
                          default_end_time - (30 * 24 * 60 * 60) - 1
                        else
                          default_end_time - (30 * 24 * 60 * 60) - 1
                        end
                       end
  query = QUERY_GENERATOR.generate_query(collect_health_checks)
  data = LOKI_CLIENT.query_range(query, Time.at(default_start_time), Time.at(default_end_time))
  services = {}
  data.each do |data_rec|
    rec = data_rec[:values]
    event_type = data_rec[:stream][:Type]
    svc_name = event_type == "container" ? rec[:Actor][:Attributes][:'com.docker.swarm.service.name'] : (event_type == "service" ? data_rec[:stream][:Actor_Attributes_name] : "default_service")
    cid = rec[:Actor][:ID]
    action = rec[:Action]
    timestamp = rec[:time]
    ext_code = rec[:Actor][:Attributes][:exitCode]
    hc_id = rec[:Actor][:Attributes][:execID]
    hc_ext_code = ext_code
    services[svc_name] ||= { containers: {}, events: [] }
    if rec[:Type] == 'container'
      services[svc_name][:containers][cid] ||= { start: nil, end: nil, latest_start: nil, events: [], health_checks: {} }
      if collect_health_checks && HEALTH_CHECK_EVENTS.any? { |event| action.include?(event)}
        services[svc_name][:containers][cid][:health_checks][hc_id] ||= !load_source_jsons ? { hc_id: hc_id, start_hc: nil, end_hc: nil, hc_ext_code: nil } : { hc_id: hc_id, start_hc: nil, end_hc: nil, hc_ext_code: nil, src_jsons: []}
        services[svc_name][:containers][cid][:health_checks][hc_id][:start_hc] = timestamp if services[svc_name][:containers][cid][:health_checks][hc_id][:start_hc].nil? || timestamp < services[svc_name][:containers][cid][:health_checks][hc_id][:start_hc]
        services[svc_name][:containers][cid][:health_checks][hc_id][:end_hc] = timestamp if services[svc_name][:containers][cid][:health_checks][hc_id][:end_hc].nil? || timestamp < services[svc_name][:containers][cid][:health_checks][hc_id][:end_hc]
        services[svc_name][:containers][cid][:health_checks][hc_id][:hc_ext_code] = hc_ext_code if !hc_ext_code.nil? && services[svc_name][:containers][cid][:health_checks][hc_id][:hc_ext_code].nil? && action.include?('exec_die')
        if load_source_jsons
          services[svc_name][:containers][cid][:health_checks][hc_id][:src_jsons] << data_rec
        end
      else
        services[svc_name][:containers][cid] ||= { start: nil, end: nil, latest_start: nil, events: [] }
        new_event = { action: action, timestamp: timestamp, ext_code: ext_code }
        if load_source_jsons
          new_event[:src_jsons] = [data_rec]
        end
        services[svc_name][:containers][cid][:events] << new_event
        services[svc_name][:containers][cid][:start] = timestamp if ((CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:start] == nil) || (services[svc_name][:containers][cid][:start] > timestamp)))
        services[svc_name][:containers][cid][:latest_start] = timestamp if ((CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:latest_start] == nil) || (services[svc_name][:containers][cid][:latest_start] < timestamp)))
        services[svc_name][:containers][cid][:end] = timestamp if ((CONTAINER_STOP_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:end] == nil) || (services[svc_name][:containers][cid][:end] < timestamp)))
      end
    elsif rec[:Type] == 'service'
      existing_event = services[svc_name][:events].find { |e| e[:action] == action && e[:timestamp] == timestamp }
      services[svc_name][:events] << (!load_source_jsons ? { action: action, timestamp: timestamp, ext_code: ext_code} : { action: action, timestamp: timestamp, ext_code: ext_code, src_jsons: [data_rec]}) unless existing_event
    end
  end
  results = {
    groups: services.map { |n, v| { id: n, name: n, type: 'service', containers: v[:containers].keys } }  +
      services.keys.flat_map { |svc_name| services[svc_name][:containers].keys.flat_map { |cid| { id: cid, name: cid, type: 'container' } } },
    items: services.keys.flat_map { |svc_name| services[svc_name][:containers].flat_map {|cid, cont| cont[:events].map {|event| { id: cid + " " + event[:action] + " " + event[:timestamp].to_s, content: event[:action], type: 'point', groupId: cid, start: event[:timestamp], ext_code: event[:ext_code], statuses: get_status_event(event), src_jsons: event[:src_jsons].to_json } } } } +    # container_events
      services.keys.flat_map { |svc_name| services[svc_name][:events].flat_map {|event| { id: "Service event: " + svc_name + " " + event[:action] + " " + event[:timestamp].to_s, content: event[:action], ext_code: event[:ext_code], type: 'point', groupId: svc_name, start: event[:timestamp], statuses: get_status_event(event), src_jsons: event[:src_jsons].to_json } } } +    # service_events
      services.keys.flat_map{ |svc_name| services[svc_name][:containers].flat_map { |cid, cont| { id: cid, content: "Container", type: 'range', myType: 'canBeExploredById', groupId: cid, start: cont[:start].nil? ? default_start_time : cont[:start] , end: cont[:end].nil? ? default_end_time : cont[:end], statuses: get_status_cont(cont[:start], cont[:end], cont[:latest_start]) } } } +   # containers
      (collect_health_checks ? services.keys.flat_map{ |svc_name| services[svc_name][:containers].flat_map { |cid, cont| cont[:health_checks].flat_map { |hc_id, hc| { id: hc_id, content: "Health check", type: 'range', myType: 'HealthCheck', groupId: cid, start: hc[:start_hc].nil? ? hc[:end_hc] : hc[:start_hc], end: hc[:end_hc].nil? ? hc[:start_hc] : hc[:end_hc], statuses: get_status_health_check(hc), ext_code: hc[:hc_ext_code], src_jsons: hc[:src_jsons].to_json } } } } : [])    # health_checks
  }
  results
end
