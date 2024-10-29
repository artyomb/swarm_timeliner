#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require_relative 'ajax'
require_relative 'timeline.rb'
require_relative 'cont_logs.rb'
# require 'sinatra/reloader'  if `hostname` =~ /yoga/i && !ENV["COMPILED"]


class Timeliner < Sinatra::Base
  register Ajax
  # register Sinatra::Reloader
  # enable :reloader
  use Rack::SassC, css_location: "#{__dir__}/../public/css", scss_location: "#{__dir__}/../css",
      create_map_file: true, syntax: :sass, check: true
  use Rack::Static, urls: %w[/css /js], root: "#{__dir__}/public/", cascade: true


  set :root, '.' #File.dirname(__FILE__)
  # set :environment, :production

  get '/', &->(){ slim :index }

  ajax_call :post, '/timeline_data' do |data|
    get_timeline_data(data)
  end

  ajax_call :post, '/get_cont_logs' do |data|
    get_container_logs(data[:cont_id])
  end

  ajax_call :post, '/get_health_checks' do |data|
    get_health_checks(data)
  end

  get '/healthcheck', &-> { 'OK' } # LOGGER.debug :healthcheck

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end

end
