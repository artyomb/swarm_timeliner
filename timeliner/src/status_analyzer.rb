def get_status_health_check(hc)
  statuses = []
  if hc[:hc_ext_code].nil?
    statuses << 'neutral'
  elsif hc[:hc_ext_code] == 0
    statuses << 'ok'
  else
    statuses << 'error'
  end
  statuses
end

def get_status_event(event)
  statuses = []
  case event[:ext_code]
  when nil
    statuses << 'neutral'
  when '0'
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