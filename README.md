# Konnected cli-flash-tool

This is the tool we use to flash and pre-flight devices after manufacturing. It's a command-line (text-based) program
written in Ruby that downloads firmware, flashes the device, and optionally generates and prints a label.

## Prerequisites

This tool was written and tested on a Mac, but should work on Linux just as well. It may need some modification to run
on Windows.

### Ruby

Requires the [ruby version specified](.ruby-version). Recommended to use [rbenv](https://github.com/rbenv/rbenv) to 
manage Ruby versions.

```zsh
brew install rbenv ruby-build       # Mac
# or
sudo apt install rbenv              # Debian/Ubuntu

rbenv init
rbenv install 3.2.2
```

### esptool
Requires [esptool](https://github.com/espressif/esptool) to flash and communicate with the ESP.

```shell
brew install esptool                # Mac
pip install esptool                 # any system with Python
```

### ~/Downloads directory
The program will download firmware images to `~/Downloads`. Make sure this directory exists!

## Installation

Steps to install and set up this program. 

### Clone or download this repo:
Open a terminal window and navigate to your preferred workspace directory, then run:
```shell
git clone https://github.com/konnected-io/cli-flash-tool.git 
```

Or, download the ZIP of this repo from Github.

### Bundle
Installs all Ruby dependencies
```shell
cd cli-flash-tool
bundle
```

### Setup `config.yaml`
Copy the `config.yaml.example` file in the root of this repo to `config.yaml`:
```shell
cp config.yaml.example config.yaml
```

Now edit the `config.yaml` with your settings and preferences. Here's an example:
```yaml
flash: true
network_check: true
label_printer:
  enabled: true
  type: pdf
  name: Brother_QL_810W
  ip: 192.168.1.33
serial_port_pattern: /dev/cu.usbserial*
```

#### flash
Set to `true` to flash the firmware, otherwise firmware will not be modified.

#### network_check
Set to `true` to run the Alarm Panel Pro network check.

#### label_printer
* *enabled* - `true` to enable label printing
* *type* - `zpl` if using a Zebra printer, otherwise `pdf`
* *name* - The CUPS name of the printer (use `lpstat -a`)
* *ip* - The IP address of the printer (only needed when using Zebra printers)

#### serial_port_pattern
A file path pattern to scan for devices connected via USB/UART ports.

## Running
Run the program by executing it in Ruby:
```shell
bundle exec ruby cli_flash_tool.rb
```

Follow on-screen prompts to select the product and download the firmware image. Once the flash tool starts,
plug in your device to a USB hub and it will start flashing automatically!

Press `CTRL-C` to exit.
