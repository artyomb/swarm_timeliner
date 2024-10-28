require 'rest-client'
require 'json'
require 'docker'

Docker.url = 'unix:///var/run/docker.sock'

def get_container_logs(container_id)
  begin
    container = Docker::Container.get(container_id)
    logs - container.logs(stditout: true, stderr: true)
    {status: "SUCCESS", logs: "logs "}.to_json
  rescue Docker::Error::NotFoundError
    { status: "ERROR", message: "Container not found" }.to_json
  rescue Docker::Error::TimeoutError
    { status: "ERROR", message: "Request to Docker timed out" }.to_json
  rescue StandardError => e
    { status: "ERROR", message: "Unexpected error: #{e.message}" }.to_json
  end
end
