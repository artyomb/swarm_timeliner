require 'rest-client'
require 'json'
require 'docker'

Docker.url = 'unix:///var/run/docker.sock'

def get_container_logs(container_id)
  begin
    container = Docker::Container.get(container_id)
    logs = container.logs(stdout: true, stderr: true, encoding: 'UTF-8')
    { status: 'SUCCESS', message: logs.force_encoding('UTF-8') }.to_json
  rescue Docker::Error::NotFoundError
    { status: 'ERROR', message: 'Container not found' }.to_json
  rescue Docker::Error::TimeoutError
    { status: 'ERROR', message: 'Request to Docker timed out' }.to_json
  rescue Encoding::UndefinedConversionError => e
    { status: 'ERROR', message: "Encoding error: #{e.message}" }.to_json
  rescue StandardError => e
    { status: 'ERROR', message: "Unexpected error: #{e.message}" }.to_json
  end
end

# Without encoding responses with errors: Unexpected error: "\xE4" from ASCII-8BIT to UTF-8