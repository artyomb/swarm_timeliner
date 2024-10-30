# # frozen_string_literal: true
#
# require 'net/http'
# require 'json'
# require 'logger'
#
# class LokiClient
#   Error = Class.new(StandardError)
#   TimeoutError = Class.new(Error)
#   APIError = Class.new(Error)
#
#   using Module.new {
#     refine Time do
#       def to_nano
#         to_i * 1_000_000_000
#       end
#     end
#   }
#
#   DEFAULT_OPTIONS = {
#     limit: 10_000,
#     retries: 3,
#     timeout: 10,
#     batch_size: 1_000,
#     logger: Logger.new($stdout)
#   }.freeze
#
#   def initialize(host, port: 3100, **options)
#     @options = DEFAULT_OPTIONS.merge(options)
#     @http = Net::HTTP.new(host, port).tap do |http|
#       http.read_timeout = @options[:timeout]
#       http.use_ssl = port == 443
#     end
#     @logger = @options[:logger]
#   end
#
#   def query_range(query, start_time, end_time)
#     start_nano = start_time.to_nano
#     end_nano = end_time.to_nano
#
#     Enumerator.new do |yielder|
#       current = start_nano
#       while current < end_nano
#         fetch_chunk(query, current, end_nano).each do |entry|
#           yielder << entry
#         end
#         break if current == end_nano
#       end
#     end
#   end
#
#   private
#
#   def fetch_chunk(query, start_time, end_time)
#     retries = 0
#     params = build_params(query, start_time, end_time)
#
#     begin
#       response = @http.get("/loki/api/v1/query_range?#{params}")
#       handle_response(response)
#     rescue StandardError => e
#       retries += 1
#       retry if retries <= @options[:retries] && should_retry?(e)
#       raise Error, "Failed after #{retries} retries: #{e.message}"
#     end
#   end
#
#   def build_params(query, start_time, end_time)
#     URI.encode_www_form(
#       query: query,
#       start: start_time,
#       end: end_time,
#       limit: @options[:limit]
#     )
#   end
#
#   def handle_response(response)
#     case response
#     when Net::HTTPSuccess
#       process_successful_response(response)
#     else
#       raise APIError, "HTTP #{response.code}: #{response.body}"
#     end
#   end
#
#   def process_successful_response(response)
#     data = JSON.parse(response.body)
#     results = data.dig('data', 'result') || []
#
#     results.flat_map do |result|
#       result.fetch('values', []).map do |timestamp, value|
#         {
#           stream: result['stream'],
#           timestamp: Time.at(timestamp.to_i / 1_000_000_000),
#           value: value
#         }
#       end
#     end
#   end
#
#   def should_retry?(error)
#     case error
#     when Net::OpenTimeout, Net::ReadTimeout, TimeoutError
#       true
#     when APIError
#       error.message.include?('429') # Rate limit
#     else
#       false
#     end
#   end
# end
#
# # Usage:
# begin
#   client = LokiClient.new('loki.example.com', logger: Logger.new($stdout))
#
#   logs = client.query_range(
#     '{job="nginx"}',
#     Time.new(2022, 11, 30, 12, 0),
#     Time.new(2022, 11, 30, 13, 0)
#   )
#
#   logs.lazy
#       .select { |log| log[:value].include?('error') }
#       .take(100)
#       .each { |log| puts "#{log[:timestamp]} - #{log[:value]}" }
# rescue LokiClient::Error => e
#   puts "Error: #{e.message}"
# end