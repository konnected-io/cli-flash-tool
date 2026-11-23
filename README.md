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

#### self_test
Settings for the GDO blaQ self-test mode (see [Self-test](#self-test-gdo-blaq) below):
* *enabled* - default answer at the "Self-test before flashing?" prompt
* *sheet_id* / *sheet_tab* - Google Sheet that results are appended to
* *wifi_ssid* / *min_rssi* - optional: require this SSID in the device's WiFi scan at this strength
* *report_timeout* - seconds to wait for the device's report (default 180)
* *firmware* - optional local self-test `.bin`, instead of the one attached to the latest release

## Running
Run the program by executing it in Ruby:
```shell
bundle exec ruby cli_flash_tool.rb
```

Follow on-screen prompts to select the product and download the firmware image. Once the flash tool starts,
plug in your device to a USB hub and it will start flashing automatically!

Press `CTRL-C` to exit.

## Self-test (GDO blaQ)

For returned units (or any unit you want checked before it ships), pick **Garage Door Opener blaQ**,
then **Self-test + flash** at the next prompt. For each unit the tool:

1. Erases the chip and writes the self-test firmware (`konnected-esphome-selftest-GDOv2-Q-*.bin`
   from the latest konnected-esphome release, or `self_test.firmware`).
2. Waits for its report over USB. The unit plays a rising tone when it's ready: press the test
   harness onto the terminals (the slot shows **APPLY HARNESS**). If contact slips it plays a
   two-note tone and retries, up to 3 times.
3. Asks the operator to confirm the light/sound pattern — blue LED, white LEDs, a beep. Press
   **y** or **n** (with several units waiting, press the slot number first).
4. **Pass:** writes the stock firmware, pre-registers the device in Konnected Cloud (resetting
   a returned unit's record as new), and prints the normal label.
   **Fail:** appends a row to the results sheet and prints a failure label with the reason and
   the sheet row number, to stick on the unit for repair.

Every unit, pass or fail, gets a sheet row, and a copy goes to `self-test-results.jsonl`.

### Test harness

No garage door opener is needed. The harness is:
* 12V into the barrel jack
* a **2.2kΩ** resistor from that same 12V to the blaQ's Security+ data terminal (the one wired to
  the opener's red terminal), and the 12V ground to the blaQ's ground terminal (white)

It can be screwed in or just held against the terminals.

### Google Sheet access

Results are written with a Google service account. Set `GOOGLE_APPLICATION_CREDENTIALS` in `.env`
to the account's JSON key file, and share the sheet with the account's email as an **Editor**.

### Failure reasons

| Label | Meaning |
|---|---|
| `NO CONTACT/0V` | the harness never made contact in 45s — or the bus is shorted / TX stuck on |
| `BUS AT 0V` | the line read 0V during the test |
| `BUS ECHO 1200` / `BUS ECHO 9600` | bytes sent on TX didn't come back on RX (Security+ 1.0 / 2.0 format) |
| `WIFI RF` | no access points, or `wifi_ssid` missing / weaker than `min_rssi` |
| `LED/BUZZER` | operator rejected the light/sound pattern |
| `NO TEST REPORT` | the self-test firmware never reported (didn't boot?) |
| `FLASH FAIL` | esptool couldn't write the self-test or stock firmware |

`+N` after a reason means N more checks also failed; the sheet row has the details.
