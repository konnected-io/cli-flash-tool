require './lib/generic_preflight.rb' 

class GdoPreflight < GenericPreflight

  @product_name = 'Garage Door Opener (v2)'

  def self.download_firmware
    github_releases_url = 'https://api.github.com/repos/konnected-io/konnected-esphome/releases/latest'
    key = 'konnected-esphome-garage-door-esp32'
    release_json = JSON.parse(Net::HTTP.get(URI(github_releases_url)))
    release = release_json['assets'].detect{|asset| asset['name'].start_with?(key) }
    download_url = release['browser_download_url']
    @filename = download_url.split('/').last
    puts Rainbow("Downloading #{download_url}").yellow
    URI.open(download_url) do |file|
      File.open("#{Dir.home}/Downloads/#{@filename}", "wb") do |f|
        f.write(file.read)
      end
    end
  end

  def self.firmwares 
    @filename
  end

  def start
    flash_firmware
    generate_label
    print_label
    finish
  end

  def generate_label
    batchnum = Time.now.strftime "%y%m"
    @runner.update_status port, Rainbow("Generating label: #{@device_id}").yellow
    label = Zebra::Zpl::Label.new(
      width:        203,
      length:       101,
      print_speed:  3
    )
  
    label << Zebra::Zpl::Text.new(
      data: "GDOv2-S",
      position: [20,20],
      font_size: Zebra::Zpl::FontSize::SIZE_2
    )
    label << Zebra::Zpl::Text.new(
        data:       "ID: #{@device_id}",
        position:   [20, 50],
        font_size:  Zebra::Zpl::FontSize::SIZE_1,
      )
  
    label << Zebra::Zpl::Text.new(
        data: "Batch: #{batchnum}",
        position: [20, 70],
        font_size: Zebra::Zpl::FontSize::SIZE_1
      )
  
    label << Zebra::Zpl::Datamatrix.new(
        data:             @device_id,
        position:         [150,20],
        symbol_height:     3
      )
  
    @zpl = ''
    label.dump_contents @zpl
    # TODO: send to printer
  end

end
