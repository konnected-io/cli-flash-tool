class PreflightRunner

    attr_reader :config, :batchnum

    def initialize
      @config = Config.new
      @ports = Hash.new
      @started_at = Time.now
      @success_count = 0
      @failure_count = 0
      @threads = {}
      @self_test = false
      @pending_confirm = {}   # port => Queue, units waiting on the operator
      @confirm_mutex = Mutex.new
      @selected_slot = nil
    end

    def run
      sso_credentials
      select_product
      set_batchnum
      select_mode
      start_key_reader if self_test?
      while true do
        sleep 1
        Dir[config.serial_port_pattern].each do |port|
          # A unit mid-job can drop off USB for a moment (the ESP32-S3's native
          # USB re-enumerates on every chip reset). Never start a second job
          # on a port whose first one is still running.
          next if @threads[port]&.alive?

          if @ports[port].nil? || @ports[port].start_with?("\e[38;5;102m")
            @ports[port] = 'connected'
          end

          if @ports[port] == 'connected'
            device = @device_class.new(port, self)
            @ports[port] = 'checking'
            @threads[port] = Thread.new do
              device.start
            rescue StandardError => e
              update_status(port, Rainbow("ERROR: #{e.class}: #{e.message}").red.inverse)
            end
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
      puts "[3] Garage Door Opener White (v2-S)"
      puts "[4] Garage Door Opener blaQ (v2-Q)"
      puts "[5] 6-zone Alarm Panel"
      puts "---"
      puts "[6] NextgenID custom Pro firmware"
      product_id = STDIN.gets.strip
      case product_id.to_i
        when 1
          @device_class = ProPreflight
          @device_class.download_firmware
        when 2
          @device_class = GdoV1sPreflight
          @device_class.download_firmware
        when 3
          @device_class = GdoV2sPreflight
          @device_class.download_firmware
        when 4
          @device_class = GdoV2qPreflight
          @device_class.download_firmware
        when 5
          @device_class = ApPreflight
          @device_class.download_firmware
        when 6
          @device_class = ProPreflight
          @device_class.nextgenid_firmware
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

    # Self-test mode is offered for products that support it (returned units).
    def select_mode
      @self_test = false
      return unless @device_class.respond_to?(:download_self_test_firmware)

      default_test = self_test_settings[:enabled] == true
      puts %x{clear}
      puts Rainbow("\nSelf-test before flashing?").green.inverse
      puts "[1] Flash only#{' (default)' unless default_test}"
      puts "[2] Self-test + flash: returned units, needs the test fixture#{' (default)' if default_test}"
      entry = STDIN.gets.strip
      @self_test = entry.blank? ? default_test : entry == '2'
      return unless @self_test

      @device_class.download_self_test_firmware(self_test_settings[:firmware])
      if self_test_settings[:sheet_id].blank?
        puts Rainbow("WARNING: self_test.sheet_id is not set in config.yaml; results go to the local log only").yellow
        sleep 3
      end
    end

    def self_test?
      @self_test
    end

    def self_test_settings
      settings = config.respond_to?(:self_test) ? config.self_test : nil
      (settings || {}).with_indifferent_access
    end

    def results_sheet
      @results_sheet ||= ResultsSheet.new(
        sheet_id: self_test_settings[:sheet_id],
        tab: self_test_settings[:sheet_tab] || 'Results'
      )
    end

    # Blocks the calling unit's thread until the operator answers for its slot.
    # Returns true / false, or nil if the unit was unplugged before an answer.
    def ask_operator(port, question)
      queue = Queue.new
      @confirm_mutex.synchronize { @pending_confirm[port] = queue }
      update_status(port, Rainbow("CONFIRM [#{slot_of(port)}]: #{question}  y / n").black.bg(:yellow))
      gone_since = nil
      loop do
        answer = queue.pop(timeout: 1)
        unless answer.nil?
          update_status(port, Rainbow(answer == :yes ? 'Operator: OK' : 'Operator: REJECTED').yellow)
          return answer == :yes
        end

        # A brief USB drop is normal; a few seconds gone means it was unplugged.
        gone_since = File.exist?(port) ? nil : (gone_since || Time.now)
        next unless gone_since && Time.now - gone_since > 5

        @confirm_mutex.synchronize { @pending_confirm.delete(port) }
        return nil
      end
    end

    def increment_failure
      @failure_count += 1
    end

    def cleanup
      @ports.each do |port,_|
        next if @threads[port]&.alive?
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
      puts Rainbow(@device_class.product_name + (self_test? ? '  [SELF-TEST + FLASH]' : '')).green
      puts Rainbow("CTRL-C to exit").gray
      counts = "Elapsed: #{elapsed_time}   Flashed: #{@success_count}"
      counts += "   Failed: #{@failure_count}" if self_test?
      puts counts + "\n\n"
      @ports.each do |name, status|
        puts "[#{slot_of(name)}] #{name}: #{status}\n"
      end
      if self_test? && @pending_confirm.any?
        hint = if @pending_confirm.size == 1
          'Press y (pass) or n (fail)'
        else
          "Press a slot number, then y / n#{@selected_slot ? "   (slot #{@selected_slot} selected)" : ''}"
        end
        puts "\n" + Rainbow(hint).black.bg(:yellow)
      end
      puts "\n\n"
    end

    # Stable 1-based number per port, in the order ports were first seen.
    def slot_of(port)
      @ports.keys.index(port).to_i + 1
    end

    # Self-test answers come from single keypresses while the status screen
    # redraws. cbreak mode (not raw) keeps output formatting and CTRL-C intact.
    def start_key_reader
      saved = `stty -g`.strip
      at_exit { system("stty #{saved}") }
      system('stty -icanon -echo min 1')
      Thread.new do
        while (key = STDIN.getc)
          handle_key(key.downcase)
        end
      end
    end

    def handle_key(key)
      @confirm_mutex.synchronize do
        case key
        when /\A[1-9]\z/
          @selected_slot = key.to_i
        when 'y', 'n'
          port = if @pending_confirm.size == 1
            @pending_confirm.keys.first
          elsif @selected_slot
            @pending_confirm.keys.detect { |p| slot_of(p) == @selected_slot }
          end
          return unless port

          @pending_confirm.delete(port).push(key == 'y' ? :yes : :no)
          @selected_slot = nil
        end
      end
    end

    def update_status(port, status)
      @ports[port] = status
    end

    def sso_credentials
      begin
        @sso_credentials ||= Aws::SSOCredentials.new(
          sso_account_id: '684083964462',
          sso_role_name: 'Flasher',
          sso_region: "us-east-1",
          sso_session: 'my-sso'
        )
      rescue Aws::Errors::InvalidSSOToken
        IO.popen("aws sso login --sso-session my-sso") do |io|
          while line = io.gets do
            puts Rainbow(line).aqua
          end
        end
        sso_credentials
      end
    end

  end
  