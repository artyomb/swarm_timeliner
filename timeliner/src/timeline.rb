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
  items = {}
  data.each do |rec|
    if rec[:Type] == 'container'
      cid = rec[:Actor][:ID]
      svc_name = rec[:Actor][:Attributes][:'com.docker.swarm.service.name']

      services[svc_name] ||= { containers: {}, events: [] }

      # if (CONTAINER_START_ACTIONS + CONTAINER_STOP_ACTIONS).include? rec[:Action]
        items[cid] = services[svc_name][:containers][cid] ||= { group: svc_name }
        items[cid][:start] = rec[:time] if CONTAINER_START_ACTIONS.include? rec[:Action]
        items[cid][:end] = rec[:time] if CONTAINER_STOP_ACTIONS.include? rec[:Action]

        items[cid+'e'] ||= { group: svc_name, type: 'point', content: rec[:Action] }
        items[cid+'e'][:start] = rec[:time]
      # end
    end

    # if rec[:Type] == 'service'
    #   svc_name = rec[:Actor][:Attributes][:'com.docker.swarm.service.name']
    #   services[svc_name] ||= { containers: {}, events: [] }
    #
    #   # update, ...
    #   services[:events] << {a:1 }
    # end
  end

 {
    groups: services.map{ |n, v| {id: n, content: n}},
    items: items.map{ |id, c| { id: id[/\d+/,1], **c,
                                start: (c[:start] || (Time.now - 60*60*1).to_i),
                                # end: (c[:end] || Time.now.to_i)
    }}
  }
end
