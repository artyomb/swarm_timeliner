#!/bin/env ruby
require 'sinatra/base'
require 'slim'
require 'rack/sassc'
require_relative 'ajax'
# require 'sinatra/reloader'  if `hostname` =~ /yoga/i && !ENV["COMPILED"]


class Timeliner < Sinatra::Base
  register Ajax
  # register Sinatra::Reloader
  # enable :reloader

  use Rack::SassC, css_location: "#{__dir__}/../public/css", scss_location: "#{__dir__}/../css",
      create_map_file: true, syntax: :sass, check: true
  use Rack::Static, urls: [''], root: "#{__dir__}/public/", cascade: true

  set :root, '.' #File.dirname(__FILE__)
  # set :environment, :production

  get '/', &->(){ slim :index }

  ajax_call :post, '/gantt_api/task' do |data|
    { action: 'inserted', tid: 1 }
  end

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck

  error do
    "<h1>Error: #{env['sinatra.error']}</h1> <pre>#{env['sinatra.error'].backtrace.join("\n")}</pre>"
  end

end
