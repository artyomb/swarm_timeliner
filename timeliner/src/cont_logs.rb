require 'rest-client'
require 'json'
require 'docker'

Docker.url = 'unix:///var/run/docker.sock'

def get_container_logs(container_id)
  begin
    container = Docker::Container.get(container_id)
    logs = container.logs(stdout: true, stderr: true)
    logs = logs.encode('UTF-8', "ISO-8859-15")
    { status: "SUCCESS", message: logs }
  rescue Docker::Error::NotFoundError
    { status: "ERROR", message: "Container not found" }
  rescue Docker::Error::TimeoutError
    { status: "ERROR", message: "Request to Docker timed out" }
  rescue StandardError => e
    { status: "ERROR", message: "Unexpected error: #{e.message}" }
  end
end