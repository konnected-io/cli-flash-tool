require 'serialport'

# The result block printed by the device self-test firmware
# (konnected-esphome: garage-door-GDOv2-Q-selftest.yaml). The firmware logs it
# over USB serial, and re-prints it every few seconds, as:
#
#   [I][ktest:234]: KTEST BEGIN format=2 fw=1.1.0 mac=64e833692dec
#   [I][ktest:236]: KTEST bus_idle PASS busy=0/200
#   [I][ktest:236]: KTEST echo_1200_8e1 PASS rx=32/32
#   [I][ktest:236]: KTEST wifi_ap INFO -41 "Office"
#   [I][ktest:238]: KTEST END PASS
class SelfTestReport
  # The report format this tool understands. Must match REPORT_FORMAT in the
  # firmware's gdo_selftest.cpp.
  FORMAT = 2

  Result = Struct.new(:name, :verdict, :detail)

  attr_reader :format, :fw, :mac, :verdict, :results

  ANSI = /\e\[[0-9;]*m/
  BEGIN_LINE = /KTEST BEGIN (.*)$/
  RESULT_LINE = /KTEST (\S+) (PASS|FAIL|INFO) ?(.*)$/
  END_LINE = /KTEST END (PASS|FAIL)/
  STATUS_LINE = /KTEST STATUS (.*)$/

  def initialize(header, results, verdict)
    fields = header.scan(/(\w+)=(\S+)/).to_h
    @format = fields['format']&.to_i
    @fw = fields['fw']
    @mac = fields['mac']
    @results = results
    @verdict = verdict
  end

  def passed?
    @verdict == 'PASS' && failures.empty?
  end

  def failures
    @results.select { |r| r.verdict == 'FAIL' }
  end

  def [](name)
    @results.detect { |r| r.name == name }
  end

  # [[ssid, rssi], ...] strongest first, from the wifi_ap INFO lines.
  def access_points
    @results.select { |r| r.name == 'wifi_ap' }.filter_map do |r|
      m = r.detail.match(/\A(-?\d+) "(.*)"\z/)
      [m[2], m[1].to_i] if m
    end
  end

  # Feeds log text in; returns a complete report once a BEGIN..END block has
  # been seen, nil until then.
  class Parser
    # Latest `KTEST STATUS` progress text not yet collected by #take_status.
    def take_status
      status, @status = @status, nil
      status
    end

    def initialize
      @buffer = +''
      @header = nil
      @results = []
    end

    def <<(chunk)
      @buffer << chunk
      report = nil
      while (newline = @buffer.index("\n"))
        line = @buffer.slice!(0..newline).gsub(ANSI, '').strip
        report ||= consume(line)
      end
      report
    end

    private

    def consume(line)
      if (m = line.match(STATUS_LINE))
        @status = m[1]
      elsif (m = line.match(BEGIN_LINE))
        @header = m[1]
        @results = []
      elsif @header && (m = line.match(END_LINE))
        report = SelfTestReport.new(@header, @results, m[1])
        @header = nil
        return report
      elsif @header && (m = line.match(RESULT_LINE))
        @results << Result.new(m[1], m[2], m[3])
      end
      nil
    end
  end

  # Waits for the device on `port` to print a complete report. Tolerates the
  # port disappearing and coming back, which an ESP32-S3's native USB does on
  # every chip reset. Yields status strings for the UI. Returns nil on timeout.
  def self.read(port, timeout:)
    deadline = Time.now + timeout
    parser = Parser.new

    while Time.now < deadline
      unless File.exist?(port)
        yield "waiting for #{File.basename(port)} to come back" if block_given?
        sleep 0.25
        next
      end

      begin
        SerialPort.open(port, 115200, 8, 1, SerialPort::NONE) do |sp|
          # On the S3's USB-Serial-JTAG, RTS=1 with DTR=0 resets the chip and
          # DTR=1 at reset release selects download mode. Opening the port
          # asserts both; dropping RTS first walks (1,1) -> (0,1) -> (0,0),
          # which never resets it, let alone into the bootloader.
          sp.rts = 0
          sp.dtr = 0
          while Time.now < deadline
            next unless IO.select([sp], nil, nil, 0.5)

            report = parser << sp.read_nonblock(4096)
            return report if report

            status = parser.take_status
            yield status if status && block_given?
          end
        end
      rescue IO::WaitReadable
        retry
      rescue EOFError, Errno::ENXIO, Errno::EIO, Errno::ENOENT, Errno::EBUSY, IOError
        # Device reset or re-enumerated mid-read: reopen and keep going.
        sleep 0.25
      end
    end
    nil
  end
end
