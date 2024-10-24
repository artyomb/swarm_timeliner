require 'time'

require_relative 'service_action'


class TimeRangeItemForVis
  attr_accessor :id, :group, :start, :end, :content, :continuous

  def initialize(container)
    @id = container.container_id
    @group = container.service_name
    container_start_time_known = false

    begin
      @start = container.actions.select { |action| action.action_name.include?("start") }.map(&:timestamp_nano).min
      container_start_time_known = true
    rescue StandardError
      @start = (Time.now.utc.change(hour: 0, min: 0, sec: 0, usec: 0).to_f * 1e9).to_i
    end

    currently_running = false

    begin
      @end = container.actions.select { |action| %w[stop exit kill].any? { |status| action.action_name.include?(status) } }
                      .map(&:timestamp_nano).max
    rescue StandardError
      currently_running = true
      @end = -1
    end

    if currently_running
      @content = "Currently running: starttime #{container_start_time_known ? nanoseconds_to_datetime(@start) : 'unknown'}"
    else
      time_range = nanoseconds_to_time(Time.now.to_i * 1e9.to_i - @start)
      @content = "Container worked for: #{time_range}" + (container_start_time_known ? '' : ' or more')
    end

    @continuous = @end == -1
  end

  def to_dict
    {
      id: @id,
      group: @group,
      start: @start,
      end: @end,
      content: @content,
      continuous: @continuous
    }
  end

  def to_s
    to_dict.to_s
  end
end

class TimePointItemForVis
  attr_accessor :id, :group, :timestamp, :type, :content

  def initialize(service_action)
    @id = "Service #{service_action.service_name}(id=#{service_action.actor_id}): #{service_action.action} at #{service_action.timestamp_nano}"
    @group = service_action.service_name
    @timestamp = service_action.timestamp_nano
    @type = 'point'
    @content = service_action.action
  end

  def to_dict
    {
      id: @id,
      group: @group,
      timestamp: @timestamp,
      type: @type,
      content: @content
    }
  end

  def to_s
    to_dict.to_s
  end
end

def   get_groups_and_items_from_service_container_actions_entries(result_list_for_container_events)
  groups = Set.new
  items = []

  result_list_for_container_events.each do |service|
    service.containers.each do |container|
      items << TimeRangeItemForVis.new(container)
    end
    groups.add(service.service_name)
  end

  [groups, items]
end

def get_groups_and_items_from_service_actions_entries(result_list_for_service_events)
  groups = Set.new
  items = []

  result_list_for_service_events.each do |service_action|
    groups.add(service_action.service_name)
    items << TimePointItemForVis.new(service_action)
  end

  [groups, items]
end

def merge_groups_and_items_from_services_and_containers_actions(container_groups, container_items, service_groups, service_items)
  container_groups.merge(service_groups)
  items = container_items + service_items
  [container_groups, items]
end

def nanoseconds_to_time(nanoseconds)
  seconds = nanoseconds / 1_000_000_000
  days, seconds = seconds.divmod(86_400)
  hours, seconds = seconds.divmod(3_600)
  minutes, seconds = seconds.divmod(60)
  format('%d d:%02d h:%02d m:%02d s', days, hours, minutes, seconds)
end

def nanoseconds_to_datetime(timestamp_nano)
  timestamp_seconds = timestamp_nano / 1e9
  Time.at(timestamp_seconds).utc.strftime('%Y.%m.%d %H:%M:%S%Z')
end
