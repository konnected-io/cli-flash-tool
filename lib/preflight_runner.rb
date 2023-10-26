class PreflightRunner

    SERIAL_PORT_PATTERN="/dev/cu.usbserial*"

    attr_reader :config, :batchnum

    def initialize
      @config = Config.new
      @ports = Hash.new
      @started_at = Time.now
      @success_count = 0
      @failure_count = 0
    end
  
    def run
      select_product
      set_batchnum
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
      end
      sleep 
    end

    def select_product
      puts %x{clear}
      puts Rainbow("\nWhich product are we flashing?").green.inverse
      puts "[1] Alarm Panel Pro"
      puts "[2] Garage Door Opener (v1-S)"
      puts "[3] Garage Door Opener (v2-S)"
      product_id = STDIN.gets.strip
      case product_id.to_i
        when 1
          @device_class = ProPreflight
        when 2
          @device_class = GdoV1sPreflight
          @device_class.download_firmware
        when 3
          @device_class = GdoV2sPreflight
          @device_class.download_firmware
        else
          puts Rainbow("Bad entry!").yellow
          raise("You suck")
        end        
    end

    def set_batchnum
      puts %x{clear}
      batchnum = Time.now.strftime "%y%m"
      puts Rainbow("\nBatch number?").green.inverse
      puts "[ENTER] #{batchnum}"
      puts "[____] custom"
      entry = STDIN.gets.strip
      if entry.blank?
        @batchnum = batchnum
      else
        if entry.match(/\A\d{4}\Z/)
          @batchnum = entry
        else
          puts Rainbow("Bad entry! Batch nubmer should be a 4-digit YYMM").yellow
          raise("Invalid batch number")
        end
      end
    end

    def cleanup
      @ports.each do |port,_|
        unless File.exist?(port)
          device_id = @ports[port].scan(/[0-9a-f]{12}/)[0]
          @ports[port] = Rainbow(device_id).dimgray
        end
      end
    end
  
    def elapsed_time
      seconds = (Time.now - @started_at).to_i
      "#{seconds / 60}:" + "%02d" % (seconds % 60)
    end

    def increment_success
      @success_count += 1
    end

    def print_status
      puts %x{clear}
      puts Rainbow("Konnected CLI Flash Tool").cyan.inverse
      puts Rainbow("konnected.io").aqua
      puts Rainbow(@device_class.product_name).green
      puts Rainbow("CTRL-C to exit").gray
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
  