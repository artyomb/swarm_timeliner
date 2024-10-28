require 'rest-client'
require 'json'

def get_container_logs(container_id)
  docker_sock_url = "http://localhost/containers/#{container_id}/logs?stdout=true&stderr=true"

  begin
    # Sending a request to the Docker API via the Docker socket
    response = RestClient::Request.execute(
      method: :get,
      url: docker_sock_url,
      headers: { 'Content-Type': 'application/json' },
      socket: '/var/run/docker.sock' # Connects directly to Docker socket
    )
    response.body
  rescue RestClient::ExceptionWithResponse => e
    { status: "ERROR", message: "Failed to retrieve logs: #{e.response}" }.to_json
  rescue StandardError => e
    { status: "ERROR", message: "Unexpected error: #{e.message}" }.to_json
  end
end
