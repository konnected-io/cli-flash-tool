require 'google/apis/sheets_v4'
require 'googleauth'
require 'json'
require 'socket'

# Appends one row per self-tested unit to a shared Google Sheet, and returns
# the row number so a failed unit's label can point at it.
#
# Auth uses Google Application Default Credentials: set
# GOOGLE_APPLICATION_CREDENTIALS in .env to a service account key file, and
# share the sheet with that service account's email as an Editor.
#
# Every row is also appended to self-test-results.jsonl next to this tool, so
# a network or API failure never loses a result.
class ResultsSheet
  SCOPE = 'https://www.googleapis.com/auth/spreadsheets'.freeze
  LOCAL_LOG = File.expand_path('../self-test-results.jsonl', __dir__)

  COLUMNS = [
    ['Timestamp',       :timestamp],
    ['Device ID',       :device_id],
    ['Result',          :result],
    ['Failure',         :failure],
    ['Details',         :details],
    ['Bus idle',        :bus_idle],
    ['Echo 1200 8E1',   :echo_1200_8e1],
    ['Echo 9600 8N1',   :echo_9600_8n1],
    ['WiFi',            :wifi],
    ['LED / buzzer',    :operator],
    ['Self-test FW',    :selftest_fw],
    ['Stock FW',        :stock_fw],
    ['Batch',           :batch],
    ['Station',         :station],
    ['Repair notes',    :notes],
  ].freeze

  def initialize(sheet_id:, tab: 'Results')
    @sheet_id = sheet_id
    @tab = tab
    @mutex = Mutex.new
    @header_checked = false
  end

  # Returns the 1-based sheet row number, or nil if the sheet couldn't be
  # written (the row is still in the local log).
  def append(row)
    row = { timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'), station: Socket.gethostname }.merge(row)
    File.open(LOCAL_LOG, 'a') { |f| f.puts(row.to_json) }
    return nil if @sheet_id.blank?

    @mutex.synchronize do
      ensure_header
      body = Google::Apis::SheetsV4::ValueRange.new(values: [COLUMNS.map { |_, key| row[key].to_s }])
      resp = service.append_spreadsheet_value(
        @sheet_id, "#{@tab}!A1", body,
        value_input_option: 'RAW', insert_data_option: 'INSERT_ROWS'
      )
      # e.g. "Results!A142:O142"
      resp.updates.updated_range[/![A-Z]+(\d+)/, 1]&.to_i
    end
  rescue StandardError => e
    @last_error = e
    nil
  end

  attr_reader :last_error

  private

  def service
    @service ||= Google::Apis::SheetsV4::SheetsService.new.tap do |s|
      s.authorization = Google::Auth.get_application_default([SCOPE])
    end
  end

  def ensure_header
    return if @header_checked

    existing = service.get_spreadsheet_values(@sheet_id, "#{@tab}!A1:A1").values
    if existing.blank?
      body = Google::Apis::SheetsV4::ValueRange.new(values: [COLUMNS.map(&:first)])
      service.update_spreadsheet_value(@sheet_id, "#{@tab}!A1", body, value_input_option: 'RAW')
    end
    @header_checked = true
  end
end
