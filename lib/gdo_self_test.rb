require_relative 'self_test_report'

# Hardware self-test for returned (or new) GDO units, mixed into a preflight
# class. Flow per unit:
#
#   1. flash the self-test firmware (erases the whole chip)
#   2. read its KTEST report over USB serial
#   3. ask the operator to confirm the LED / buzzer pattern
#   4. PASS: flash stock firmware, preregister, print the normal label
#      FAIL: log a row in the results sheet, print a failure label naming the
#            reason and the sheet row
#
# Fixture: 12V into the barrel jack, plus a pull-up from that 12V to the
# Security+ data terminal (and ground to ground) -- no garage door opener.
module GdoSelfTest
  # Label-sized reason for each firmware test.
  REASONS = {
    'bus_idle'      => 'BUS STUCK',
    'echo_1200_8e1' => 'BUS ECHO 1200',
    'echo_9600_8n1' => 'BUS ECHO 9600',
    'wifi_scan'     => 'WIFI RF',
  }.freeze

  OPERATOR_QUESTION = 'Blue LED, then white LEDs, then a beep?'.freeze

  def self_test_start
    settings = @runner.self_test_settings
    # Covers up to 3 harness waits of 45s each, plus boot and WiFi.
    timeout = (settings[:report_timeout] || 180).to_i
    failures = [] # [[label reason, sheet detail], ...]
    operator = nil

    status 'SELF-TEST: flashing test firmware'
    unless flash_firmware(self.class.self_test_firmware)
      return fail_unit(failures: [['FLASH FAIL', 'could not write the self-test firmware']])
    end

    status 'SELF-TEST: running'
    report = SelfTestReport.read(port, timeout: timeout) do |msg|
      if msg.match?(/waiting for harness|re-apply/)
        @runner.update_status port, Rainbow("APPLY HARNESS: #{msg}").black.bg(:yellow)
      else
        status "SELF-TEST: #{msg}"
      end
    end

    if report.nil?
      failures << ['NO TEST REPORT', "no self-test report within #{timeout}s (did it boot?)"]
    elsif report.format != SelfTestReport::FORMAT
      failures << ['TEST FW MISMATCH', "firmware report format #{report.format.inspect}, tool expects #{SelfTestReport::FORMAT}"]
    else
      if report.mac && @device_id && report.mac != @device_id
        failures << ['ID MISMATCH', "flashed #{@device_id} but #{report.mac} reported"]
      end
      report.failures.each do |r|
        reason = REASONS.fetch(r.name, r.name.upcase)
        # A dead-low line also means the fixture isn't making contact; say so
        # rather than implying a stuck transistor.
        reason = 'BUS AT 0V' if r.name == 'bus_idle' && r.detail.include?('line at 0V')
        reason = 'NO CONTACT/0V' if r.name == 'bus_idle' && r.detail.include?('no harness contact')
        failures << [reason, "#{r.name}: #{r.detail}"]
      end
      wifi = check_wifi(report, settings)
      failures << wifi if wifi
    end

    # Only spend the operator's time once the automated checks have passed.
    if failures.empty?
      operator = @runner.ask_operator(port, OPERATOR_QUESTION)
      if operator.nil?
        # Pulled before anyone judged it: not a result, so no row and no label.
        @runner.update_status port, Rainbow("#{@device_id}: unplugged before the LED / buzzer check - retest").yellow
        return
      end
      failures << ['LED/BUZZER', 'operator: LED / buzzer pattern not right'] unless operator
    end

    return fail_unit(failures: failures, report: report, operator: operator) if failures.any?

    status 'SELF-TEST PASSED: flashing stock firmware'
    unless flash_firmware
      return fail_unit(failures: [['FLASH FAIL', 'could not write the stock firmware']], report: report, operator: operator)
    end

    if @runner.config.preregister && !preregister
      # A cloud problem, not a device fault: keep the record, skip the label.
      record(result: 'PASS', report: report, operator: operator, notes: 'preregister failed; re-run flash-only')
      return
    end

    record(result: 'PASS', report: report, operator: operator)
    if @runner.config.label_printer[:enabled]
      generate_label
      print_label
    end
    finish
  end

  private

  def status(message)
    @runner.update_status port, Rainbow(message).yellow
  end

  # Optional site check on top of the firmware's lenient RSSI floor: require a
  # known SSID (e.g. the office AP) at a minimum signal strength.
  def check_wifi(report, settings)
    ssid = settings[:wifi_ssid]
    return nil if ssid.blank?

    min = (settings[:min_rssi] || -70).to_i
    _, rssi = report.access_points.detect { |name, _| name == ssid }
    return ['WIFI RF', "#{ssid} not seen in scan"] unless rssi
    return ['WIFI RF', "#{ssid} at #{rssi} dBm, need >= #{min}"] if rssi < min

    nil
  end

  def fail_unit(failures:, report: nil, operator: nil)
    reason = failures.first[0]
    reason += " +#{failures.size - 1}" if failures.size > 1
    details = failures.map(&:last).join('; ')

    status "FAIL: #{reason} - recording"
    row = record(result: 'FAIL', failure: reason, details: details, report: report, operator: operator)

    if @runner.config.label_printer[:enabled] && @device_id
      generate_failure_label(reason, row)
      print_label
    end

    @runner.increment_failure
    where = row ? "row #{row}" : "NOT IN SHEET (#{@runner.results_sheet.last_error&.message&.slice(0, 60)})"
    id = @device_id || 'unknown device - label by hand'
    @runner.update_status port, Rainbow("FAIL #{id}: #{reason} - #{where}").red.inverse
    false
  end

  def record(result:, report: nil, operator: nil, failure: nil, details: nil, notes: nil)
    cell = lambda do |name|
      r = report && report[name]
      r ? "#{r.verdict} #{r.detail}".strip : ''
    end
    wifi = if report
      aps = report.access_points.first(3).map { |name, rssi| "#{name} #{rssi}" }.join(', ')
      [cell.call('wifi_scan'), aps].reject(&:blank?).join(' | ')
    end

    @runner.results_sheet.append(
      device_id: @device_id || 'unknown',
      result: result,
      failure: failure,
      details: details,
      bus_idle: cell.call('bus_idle'),
      echo_1200_8e1: cell.call('echo_1200_8e1'),
      echo_9600_8n1: cell.call('echo_9600_8n1'),
      wifi: wifi,
      operator: operator.nil? ? '' : (operator ? 'OK' : 'REJECTED'),
      selftest_fw: report&.fw,
      stock_fw: result == 'PASS' ? self.class.firmwares : '',
      batch: @batchnum || @runner.batchnum,
      notes: notes
    )
  end

  # Same 1" x 0.5" stock as the shipping label:
  #
  #   FAIL: BUS ECHO 9600
  #   64e833692dec      [dm]
  #   Row 142           [dm]
  #   2026-11-23
  def generate_failure_label(reason, row)
    label = Zebra::Zpl::Label.new(width: 203, length: 101, print_speed: 3)
    label << Zebra::Zpl::Text.new(
      data: "FAIL: #{reason}", position: [15, 12], font_size: Zebra::Zpl::FontSize::SIZE_2
    )
    label << Zebra::Zpl::Text.new(
      data: @device_id, position: [15, 42], font_size: Zebra::Zpl::FontSize::SIZE_1
    )
    label << Zebra::Zpl::Text.new(
      data: row ? "Row #{row}" : 'Row: not logged', position: [15, 60], font_size: Zebra::Zpl::FontSize::SIZE_1
    )
    label << Zebra::Zpl::Text.new(
      data: Time.now.strftime('%Y-%m-%d'), position: [15, 78], font_size: Zebra::Zpl::FontSize::SIZE_1
    )
    label << Zebra::Zpl::Datamatrix.new(data: @device_id, position: [150, 42], symbol_height: 3)
    @label = label
  end
end
