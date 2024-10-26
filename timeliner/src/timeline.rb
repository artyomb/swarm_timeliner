require 'net/http'
require 'uri'
require 'json'

CONTAINER_START_ACTIONS = %w[create exec_create exec_start start]

CONTAINER_STOP_ACTIONS = %w[destroy die exec_die kill stop]


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


def get_timeline_data(data)
  limit = begin
             data[:limit].to_i
           rescue
             -1
           end || -1
  since = data[:since]

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
    svc_name = rec[:Actor][:Attributes][:'com.docker.swarm.service.name']
    cid = rec[:Actor][:ID]
    action = rec[:Action]
    timestamp = rec[:time]
    ext_code = rec[:Actor][:Attributes][:exitCode]
    services[svc_name] ||= { containers: {}, events: [] }
    if rec[:Type] == 'container'
      services[svc_name][:containers][cid] ||= { start: nil, end: nil, events: [] }
      services[svc_name][:containers][cid][:events] << { action: action, timestamp: timestamp, ext_code: ext_code }
      services[svc_name][:containers][cid][:start] = timestamp if ((CONTAINER_START_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:start] == nil) || (services[svc_name][:containers][cid][:start] > timestamp)))
      services[svc_name][:containers][cid][:end] = timestamp if ((CONTAINER_STOP_ACTIONS.include? action) && ((services[svc_name][:containers][cid][:end] == nil) || (services[svc_name][:containers][cid][:end] < timestamp)))
    end
    # if rec[:Type] == 'service'
    #   svc_name = rec[:Actor][:Attributes][:'com.docker.swarm.service.name']
    #   services[svc_name] ||= { containers: {}, events: [] }
    # end
  end

  # results = {
  #   groups: services.map{ |n, v| {id: n, content: n}},
  #   items: items.map{ |id, c| ...}
  # }
  # results [:items].append(items.map {|id,c|}})
  {
    "groups": [
      { "id": "service1", "name": "Service 1", "type": "service", "containers": ["container1", "container2"] },
      { "id": "container1", "name": "Container 1", "type": "container" },
      { "id": "container2", "name": "Container 2", "type": "container" }
    ],
    "items": [
      { "id": "event1", "content": "Service event", "type": "point", "groupId": "service1", "start": 1672531200 },
      { "id": "event2", "content": "Container 1 event", "type": "point", "groupId": "container1", "start": 1672532200 },
      { "id": "event3", "content": "Container 2 event", "type": "range", "groupId": "container2", "start": 1672533000, "end": 1672536600 }
    ]
  }
end
