class PreflightRunner

    SERIAL_PORT_PATTERN="/dev/cu.usbserial*"

    def initialize
      @device_class = ProPreflight
      @ports = Hash.new
      @started_at = Time.now
      @success_count = 0
      @failure_count = 0
    end
  
    def run
      while true do
        sleep 1
        Dir[SERIAL_PORT_PATTERN].each do |port|
          if @ports[port].nil? || @ports[port] == 'disconnected'
            @ports[port] = 'connected'
          end
          
          if @ports[port] == 'connected'
            device = @device_class.new(port, self)
            @ports[port] = 'checking'
            puts Rainbow("Device plugged in at #{port}").magenta
            Thread.new { device.start }
          end
        end
        cleanup
        print_status

        # @success_count += 1
        # seconds = (Time.now - @started_at).to_i
        # puts "## SUCCESS! "
        # puts "## Elapsed: #{"#{seconds / 60}:" + "%02d" % (seconds % 60)}"
        # puts "## Please unplug the device and affix the label.\n\n"
        # device.wait_till_unplugged
      end
      sleep 
    end

    def cleanup
      @ports.each do |port,_|
        @ports[port] = 'disconnected' unless File.exist?(port)
      end
    end
  
    def elapsed_time
      seconds = (Time.now - @started_at).to_i
      "#{seconds / 60}:" + "%02d" % (seconds % 60)
    end

    def print_status
      puts %x{clear}
      puts "Konnected CLI Flash Tool\nkonnected.io\n"
      puts "Elapsed: #{elapsed_time}   Flashed: #{@success_count}\n\n"
      @ports.each do |name, status|
        puts "#{name}: #{status}\n"
      end
      puts "\n\n"
    end

    def update_status(port, status)
      @ports[port] = status
    end

  end
  