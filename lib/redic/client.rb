require_relative "connection"
require "uri"
require "redis"

class Redic
  class Client
    EMPTY = "".freeze
    SLASH = "/".freeze

    attr_accessor :timeout

    def initialize(url, timeout)
      @semaphore = Mutex.new
      @connection = false

      configure(url, timeout)
    end

    def configure(url, timeout)
      disconnect!

      @uri = URI.parse(url)
      @timeout = timeout
    end

    def read
      #@connection.read
      @response
    end

    def write(command)
      #@connection.write(command)
      cmd_name = command.shift.to_s.downcase
      block = command.find{ |cmd| cmd.is_a? Proc }
      #binding.pry if cmd_name == "subscribe"
      @response = if command.empty?
        @connection.send(cmd_name)
      else
        @connection.send(cmd_name, *command, &block)
      end
    rescue => e
      return raise e if e.message =~ /ERR invalid DB index/
      return raise e if e.message =~  /ERR invalid password/
      @response = RuntimeError.new(e.message)
    end

    def connect
      establish_connection unless connected?

      @semaphore.synchronize do
        yield
      end
    rescue Errno::ECONNRESET
      @connection = false
      retry
    end

    def connected?
      @connection && @connection.connected?
    end

    def disconnect!
      if connected?
        @connection.disconnect!
        @connection = false
      end
    end

    def quit
      if connected?
        assert_ok(call("QUIT"))
        disconnect!

        true
      else
        false
      end
    end

  private
    def establish_connection
      begin
        #Redic::Connection.new(@uri, @timeout)
        @connection = Redis.new(url: @uri)
        raise StandardError if @connection.ping != "PONG"
      rescue StandardError => err
        raise err, "Can't connect to: #{@uri} because: #{err.message}"
      end

      if @uri.scheme != "unix"
        if @uri.password
          assert_ok(call("AUTH", @uri.password))
        end

        if @uri.path != EMPTY && @uri.path != SLASH
          assert_ok(call("SELECT", @uri.path[1..-1]))
        end
      end
    end

    def call(*args)
      @semaphore.synchronize do
        write(args)
        read
      end
    end

    def assert(value, error)
      raise error unless value
    end

    def assert_ok(reply)
      assert(reply == "OK", reply)
    end
  end
end
