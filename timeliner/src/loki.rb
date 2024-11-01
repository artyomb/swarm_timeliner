# frozen_string_literal: true

require 'net/http'
require 'json'
require 'logger'

class LokiClient
  Error = Class.new(StandardError)
  TimeoutError = Class.new(Error)
  APIError = Class.new(Error)

  using Module.new {
    refine Time do
      def to_nano
        to_i * 1_000_000_000
      end
    end
  }

  DEFAULT_OPTIONS = {
    limit: 10_000,
    retries: 3,
    timeout: 30,
    logger: Logger.new($stdout)
  }.freeze

  attr_accessor :options

  def initialize(host, port: 3100, **options)
    @options = DEFAULT_OPTIONS.merge(options)
    @http = Net::HTTP.new(host, port).tap do |http|
      http.read_timeout = @options[:timeout]
      http.use_ssl = port == 443
    end
    @logger = @options[:logger]
  end

  def query_range(query, start_time, end_time)
    start_nano = start_time.to_nano
    end_nano = end_time.to_nano

    Enumerator.new do |yielder|
      current = end_nano
      while current > start_nano
        current = fetch_chunk query, start_nano, current do |entry|
          yielder << entry
        end
      end
    end
  end
  private

  def fetch_chunk(query, start_time, end_time, &block)
    retries = 0
    params = build_params(query, start_time, end_time)

    begin
      response = @http.get("/loki/api/v1/query_range?#{params}")
      handle_response response, &block
    rescue StandardError => e
      retries += 1
      retry if retries <= @options[:retries] && should_retry?(e)
      raise Error, "Failed after #{retries} retries: #{e.message}"
    end
  end

  def build_params(query, start_time, end_time)
    URI.encode_www_form(
      query: query,
      start: start_time,
      end: end_time,
      limit: @options[:limit]
    )
  end

  def handle_response(response, &block)
    raise APIError, "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    data = JSON.parse response.body, symbolize_names: true
    earliest_in_batch = nil
    res_hash = data[:data][:result].map do |result_rec|
      current_time = Time.at(result_rec[:values][0][0].to_i / 1_000_000_000)
      earliest_in_batch = (earliest_in_batch.nil? || current_time < earliest_in_batch) ? current_time : earliest_in_batch
      {
        stream: result_rec[:stream],
        timestamp: current_time,
        values: JSON.parse(result_rec[:values][0][1], symbolize_names: true)
      }
    end
    res_hash.each(&block)
    earliest_in_batch.nil? ? 0 : earliest_in_batch.to_nano
  end

  def should_retry?(error)
    case error
    when Net::OpenTimeout, Net::ReadTimeout, TimeoutError
      true
    when APIError
      error.message.include?('429') # Rate limit
    else
      false
    end
  end
end