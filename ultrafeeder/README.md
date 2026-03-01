# Ultrafeeder

Ultrafeeder is a comprehensive ADS-B receiver and multi-feeder application that consolidates multiple ADS-B services into a single container.

## Features

- **SDR Support**: Direct RTL-SDR dongle support for receiving ADS-B signals
- **Multi-Feeder**: Feeds data to multiple ADS-B aggregators including:
  - adsb.fi
  - adsb.lol
  - airplanes.live
  - planespotters.net
  - theairtraffic.com
  - And many more...
- **TAR1090**: Modern web interface with live aircraft map on port 80 (exposed as 8080)
- **GRAPHS1090**: Built-in performance graphs and statistics
- **MLAT**: Multi-lateration support for improved tracking
- **Prometheus/InfluxDB**: Optional metrics export for monitoring

## Prerequisites

### Hardware
- RTL-SDR USB dongle (RTL2832U chipset recommended)
- Antenna suitable for 1090 MHz reception
- USB port on the Docker host

### Software
- Docker and Docker Compose
- Blacklisted RTL2832 kernel modules (see below)

## Setup

### 1. Blacklist RTL2832 Kernel Modules

To allow Docker to access the RTL-SDR device, you need to blacklist the default kernel modules:

```bash
# Copy the blacklist file to the system
sudo cp blacklist-rtl2832.conf /etc/modprobe.d/

# Reboot or reload modules
sudo modprobe -r dvb_usb_rtl28xxu rtl2832
```

### 2. Configure Environment Variables

Copy the example environment file and edit it with your details:

```bash
cp .env.example .env
nano .env
```

Required variables:
- `FEEDER_TZ`: Your timezone (e.g., Europe/London)
- `FEEDER_LAT`: Your latitude
- `FEEDER_LONG`: Your longitude
- `FEEDER_ALT_M`: Your altitude in meters
- `FEEDER_NAME`: A name for your feeder station
- `MULTIFEEDER_UUID`: A unique UUID for your station (generate with `uuidgen`). **Important**: Save this UUID - it persists your station identity and statistics across aggregators. Reuse the same UUID if redeploying.
- `ADSB_SDR_SERIAL`: The serial number of your RTL-SDR device
- `ADSB_SDR_PPM`: PPM correction value for your SDR (usually 0)

Optional variables:
- `FEEDER_HEYWHATSTHAT_ID`: HeyWhatsThat panorama ID for range rings
- `INFLUXDBURL`: InfluxDB URL for metrics
- `INFLUXDB_V2_TOKEN`: InfluxDB authentication token
- `INFLUXDB_V2_BUCKET`: InfluxDB bucket name
- `INFLUXDB_V2_ORG`: InfluxDB organization

### 3. Find Your RTL-SDR Serial Number

```bash
# Install rtl-sdr tools if not already installed
sudo apt-get install rtl-sdr

# List connected RTL-SDR devices
rtl_test
```

Look for a line like: `Serial number: 00001090`

### 4. Deploy

The service is automatically deployed via the main deployment script:

```bash
# From the repository root
./up.sh
```

Or deploy just ultrafeeder:

```bash
docker compose -f ultrafeeder/docker-compose.yaml up -d
```

## Access

Once deployed, ultrafeeder provides several interfaces:

- **TAR1090 Map**: https://ultrafeeder.viewpoint.house (or http://<host>:8080 - requires port mapping in docker-compose.yaml)
- **GRAPHS1090**: https://ultrafeeder.viewpoint.house/graphs1090
- **Prometheus Metrics**: http://<host>:9273 and http://<host>:9274
- **Raw Beast Feed**: Port 30005 (used by other feeders)

## Integration with Existing Services

Ultrafeeder can work alongside or replace existing feeder services:

- **Replaces**: Individual feeders can be consolidated into ultrafeeder
- **Coexists with**: fr24feed, piaware, planefinder, opensky if they use ultrafeeder's Beast feed on port 30005
- **Feeds data to**: The MLAT hub connection to piaware.viewpoint.house is configured

To use ultrafeeder as the primary receiver:
1. Point other feeders to use `BEASTHOST=ultrafeeder` and `BEASTPORT=30005`
2. Remove any USB device mappings from other feeders
3. Let ultrafeeder handle the SDR directly

## Storage

Ultrafeeder uses NFS4 volumes for persistent storage:
- Globe history: `/srv/nfs4/docker_nfs/ultrafeeder/globe_history`
- Graphs1090 data: `/srv/nfs4/docker_nfs/ultrafeeder/graphs1090`

## Troubleshooting

### Container won't start
1. Check the SDR is connected: `lsusb | grep RTL`
2. Verify kernel modules are blacklisted: `lsmod | grep rtl`
3. Check logs: `docker logs ultrafeeder`

### No aircraft visible
1. Verify antenna is properly connected
2. Check signal quality in the web interface
3. Ensure SDR serial number is correct in .env
4. Try adjusting `ADSB_SDR_PPM` if you know your dongle's frequency offset

### Device permission issues
The container uses device_cgroup_rules to access USB devices. Ensure Docker has permissions to access /dev/bus/usb.

## References

- [Docker ADS-B Ultrafeeder](https://github.com/sdr-enthusiasts/docker-adsb-ultrafeeder)
- [SDR-Enthusiasts Documentation](https://sdr-enthusiasts.gitbook.io/ads-b/)
- [RTL-SDR Setup](https://www.rtl-sdr.com/rtl-sdr-quick-start-guide/)
