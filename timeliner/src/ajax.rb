module Ajax

  class AJAX_Error < StandardError
    def initialize(e, response)
      $stderr.puts "Error: #{e.message}\n#{e.backtrace.join("\n")}"
      @response = response
      super
    end

    def to_json(*_args) = @response.to_json
  end

  def self.extended(base)
    base.class_eval do
      def parse_data
        data = params # rack.request.form_hash', 'rack.request.form_imput', 'rack.tempfile'
        if @env['CONTENT_TYPE'] =~ /application\/json/
          body_str = request.body.read
          body_str.force_encoding 'utf-8'
          data = body_str.empty? ? {} : JSON.parse(body_str, symbolize_names: true)
        end
        data
      end
    end
  end


  def exception2halt(&block)
    proc do |**args|
      instance_exec **args, &block
    rescue AJAX_Error => e
      halt 403, e.to_json
    end
  end

  def ajax_call(method, path, &block)
    send method, path, &exception2halt {
      content_type :json
      result = instance_exec(parse_data, &block)
      response.content_type =~ /json/ ? result.to_json : result
    }
  end
end