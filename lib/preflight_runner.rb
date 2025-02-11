class PreflightRunner

    attr_reader :config, :batchnum, :api_token

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
      check_aws_token
      while true do
        sleep 1
        Dir[config.serial_port_pattern].each do |port|
          if @ports[port].nil? || @ports[port].start_with?("\e[38;5;102m")
            @ports[port] = 'connected'
          end
          
          if @ports[port] == 'connected'
            device = @device_class.new(port, self)
            @ports[port] = 'checking'
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
      puts "[3] Garage Door Opener White (v2-S)"
      puts "[4] Garage Door Opener blaQ (v2-Q)"
      puts "[5] 6-zone Alarm Panel"
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

    def check_aws_token
      begin
        refresh_token
      rescue Aws::CognitoIdentityProvider::Errors::NotAuthorizedException, Errno::ENOENT
        konnected_cloud_authenticate
      end
    end

    private

    def refresh_token
      @api_token = begin
         res = cognito.admin_initiate_auth(
           user_pool_id: ENV['COGNITO_USER_POOL_ID'],
           client_id: ENV['COGNITO_CLIENT_ID'],
           auth_flow: 'REFRESH_TOKEN_AUTH',
           auth_parameters: {
             'REFRESH_TOKEN' => File.read('.refresh_token')
           }
         )
         res[:authentication_result][:id_token]
       end
    end

    def konnected_cloud_authenticate
      puts Rainbow("Konnected Cloud password?").magenta
      aws_password = STDIN.gets.strip
      @api_token = begin
         aws_srp = Aws::CognitoSrp.new(
           username: ENV['COGNITO_USERNAME'],
           pool_id: ENV['COGNITO_USER_POOL_ID'],
           client_id: ENV['COGNITO_CLIENT_ID'],
           password: aws_password,
           aws_client: cognito
         )
         resp = aws_srp.authenticate
         File.open('.refresh_token', 'wb') do |f|
           f.write(resp.refresh_token)
         end
         resp.id_token
       end
    end

    def cognito
      begin
        credentials = Aws::SSOCredentials.new(
          sso_account_id: '684083964462',
          sso_role_name: 'AdministratorAccess',
          sso_region: "us-east-1",
          sso_session: 'my-sso'
        )
        @cognito ||= Aws::CognitoIdentityProvider::Client.new(region: 'us-east-1', credentials: credentials)
      rescue Aws::Errors::InvalidSSOToken
        out = `aws sso login --sso-session my-sso`
        puts Rainbow(out).aqua
        
      end    
    end
  end
  