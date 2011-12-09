require "socket"

module Thin
  # A listener holding a socket and its configuration.
  class Listener
    # Hostname the socket will bind to in case of IPv4/6 addresses.
    attr_reader :host

    # Port the socket will bind to in case of IPv4/6 addresses.
    attr_reader :port

    # UNIX domain socket the socket will bind to.
    attr_reader :socket_file

    # Ruby class of the EventMachine::Connection class used to process connections.
    attr_accessor :protocol_class

    def initialize(address, options={})
      case address
      when Integer
        @host = ""
        @port = address
      when /\A(\/.*)\z/, /\Aunix:(.*)\z/ # /file.sock or unix:file.sock
        @socket_file = $1
      when /\A(?:\*:)?(\d+)\z/ # *:port or "port"
        @host = ""
        @port = $1.to_i
      when /\A((?:\d{1,3}\.){3}\d{1,3}):(\d+)\z/ # 0.0.0.0:port
        @host = $1
        @port = $2.to_i
      when /\A\[([a-fA-F0-9:]+)\]:(\d+)\z/ # IPV6 address: [::]:port
        @host = $1
        @port = $2.to_i
      else
        raise ArgumentError, "Invalid address #{address.inspect}. " +
                             "Accepted formats are: 3000, *:3000, 0.0.0.0:3000, [::]:3000, /file.sock or unix:file.sock"
      end
      
      options = {
        # Default values
        :protocol => :http,
        :tcp_no_delay => true,
        :ipv6_only => false,
        :backlog => 1024,
      }.merge(options)
      
      @backlog = options[:backlog]
      self.protocol = options[:protocol]
      self.tcp_no_delay = options[:tcp_no_delay]
      self.ipv6_only = options[:ipv6_only]
    end

    # Creates the socket and binds it to the address.
    def socket
      return @socket if @socket

      @socket = Socket.new(socket_family, Socket::SOCK_STREAM, 0)
      @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)

      @socket
    end

    # Returns the socket family: Socket::AF_*
    def socket_family
      return Socket::AF_UNIX if @socket_file
      return Socket::AF_INET6 if @host.include?(":")
      return Socket::AF_INET
    end

    # Returns +true+ if the socket is a UNIX domain one.
    def unix?
      socket_family == Socket::AF_UNIX
    end

    def ipv6_only=(value)
      socket.ipv6only! if value && !unix?
    end

    def tcp_no_delay=(value)
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, value) unless unix?
    end

    def protocol=(name_or_class)
      case name_or_class
      when Class
        @protocol_class = name_or_class
      when String
        @protocol_class = Object.const_get(name_or_class)
      when Symbol
        require "thin/protocols/#{name_or_class}"
        @protocol_class = Thin::Protocols.const_get(name_or_class.to_s.capitalize)
      else
        raise ArgumentError, "invalid protocol, use a Class, String or Symbol."
      end
    end

    def protocol
      @protocol_class.name.split(":").last
    end

    def listen
      delete_socket_file!

      socket.bind unix? ? Socket.pack_sockaddr_un(@socket_file) : # UNIX domain
                          Socket.pack_sockaddr_in(@port, @host) # IPv4/6

      socket.listen(@backlog)
    end

    def close
      socket.close if @socket
      delete_socket_file!
    end

    def to_s
      protocol + " on " + (unix? ? @socket_file :
                                   "#{@host}:#{@port}")
    end
    
    private
      def delete_socket_file!
        File.delete(@socket_file) if @socket_file && File.socket?(@socket_file)
      end
      
  end
end
