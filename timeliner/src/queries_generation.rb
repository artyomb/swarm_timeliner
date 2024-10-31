class QueriesGenerator
  # ' and Action !~ "exec.*"'
  Default_container_tracked_actions = %w[attach commit copy create destroy detach die
                              exec_detach export health_status kill
                              oom pause rename resize restart start stop top unpause update]

  Hc_events = %w[exec_start exec_create exec_die]

  Default_service_events = %w[create remove update]

  def initialize(job_value)
    @job_value = job_value
  end

  def generate_query(collect_health_checks)
    healthcheck_filter_sub_query = (!collect_health_checks ? ('" and Action !~ "exec.*') : '')
    combined_query = '{job="' + @job_value + '"} | json | ((Type = "container" and Action =~ "' +
      (Default_container_tracked_actions + (collect_health_checks ? Hc_events : [])).join('|') +
      healthcheck_filter_sub_query + '") or (Type = "service" and Action =~ "' +
      Default_service_events.join('|') + '"))'
  end
end