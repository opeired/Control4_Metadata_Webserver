# Control4 Metadata Web Screensaver

Displays Control4 now-playing metadata on web-based panels (Android tablets, browsers, etc.).

---

## Access

http://controller-ip:8089/roomid

Example:
http://192.168.1.50:8089/12

---

## Features

- Portrait and Landscape layouts
- Per-room profile overrides
- Burn-in protection
- Media and No-Media display modes
- Weather display (weather.gov)

---

## Profiles

- Auto  
- Portrait Small  
- Portrait Large  
- Landscape Small  
- Landscape Large  

---

## Composer Configuration

Global settings:
- Default Profile
- Burn-In Mode
- No-Media Layout
- Show Weather
- Weather Source

Room overrides (up to 8):
- Enabled
- Room ID
- Profile

---

## Behavior

### Media Mode
- Displays album art and metadata
- Clock moves between bottom corners
- Metadata aligns opposite the clock

### No-Media Mode
- Displays Temp / Time / Date stacked vertically
- Entire block shifts position randomly (burn-in protection)
- All elements remain aligned together (left or right)

---

## Installation

This driver must be opened and published using Control4 Driver Editor / Driver Builder before use in Composer.

---

## Notes

- URL format: http://controller-ip:8089/roomid
- Designed for kiosk-style tablets (Fully Kiosk, etc.)
- Documentation tab content must be added via Driver Editor to display in Composer
- Weather currently uses weather.gov data

---

## Version

v1.0 – Initial stable release
