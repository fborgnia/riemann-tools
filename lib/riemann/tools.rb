module Riemann
  module Tools
    require 'rubygems'
    require 'trollop'
    require 'riemann/client'
    require 'timeout'

    def self.included(base)
      base.instance_eval do
        def run
          new.run
        end

        def opt(*a)
          a.unshift :opt
          @opts ||= []
          @opts << a
        end

        def options
          p = Trollop::Parser.new
          @opts.each do |o|
            p.send *o
          end
          Trollop::with_standard_exception_handling(p) do
            p.parse ARGV
          end
        end

        opt :host, "Riemann host", :default => '127.0.0.1'
        opt :port, "Riemann port", :default => 5555
        opt :event_host, "Event hostname", :type => String
        opt :interval, "Seconds between updates", :default => 5
        opt :tag, "Tag to add to events", :type => String, :multi => true
        opt :ttl, "TTL for events", :type => Integer
        opt :attribute, "Attribute to add to the event", :type => String, :multi => true
        opt :timeout, "Timeout (in seconds) when waiting for acknowledgements", :default => 30
        opt :tcp, "Use TCP transport instead of UDP (improves reliability, slight overhead.", :default => true
        opt :daemon, "Run in background", :default => false
        opt :logfile, "logfile path", :type => String, :default => '/tmp/riemann-tools.log'
        opt :pidfile, "pidfile path", :type => String, :default => '/tmp/riemann-tools.pid'
      end
    end

    # Returns parsed options (cached) from command line.
    def options
      @options ||= self.class.options
    end
    alias :opts :options

    def attributes
      @attributes ||= Hash[options[:attribute].map do |attr|
        k,v = attr.split(/=/)
        if k and v
          [k,v]
        end
      end]
    end

    def report(event)
      if options[:tag]
        # Work around a bug with beefcake which can't take frozen strings.
        event[:tags] = options[:tag].map(&:dup)
      end

      event[:ttl] ||= (options[:ttl] || (options[:interval] * 2))

      if options[:event_host]
        event[:host] = options[:event_host].dup
      end

      event = event.merge(attributes)

      begin
        Timeout::timeout(options[:timeout]) do
          riemann << event
        end
      rescue Timeout::Error
        riemann.connect
      end
    end

    def new_riemann_client
      r = Riemann::Client.new(
        :host => options[:host],
        :port => options[:port]
      )
      if options[:tcp]
        r.tcp
      else
        r
      end
    end

    def riemann
      @riemann ||= new_riemann_client
    end
    alias :r :riemann

    def run
      daemonize if options[:daemon]
      t0 = Time.now
      loop do
        begin
          tick
        rescue => e
          $stderr.puts "#{e.class} #{e}\n#{e.backtrace.join "\n"}"
        end

        # Sleep.
        sleep(options[:interval] - ((Time.now - t0) % options[:interval]))
      end
    end

    def daemonize
      exit if fork
      Process.setsid
      $0 = self.class.name.downcase.gsub('::','_')
      $stdout.reopen(opts[:logfile], 'w')
      $stdout.sync = true
      $stderr.reopen($stdout)
      exit if fork
      f = File.new(opts[:pidfile], 'w')
      f.write Process.pid
      f.close
    end

    def tick
    end

  end
end
