# whc-lidar-ios

RoomPlan scanner demo with minimal JSON export and USDZ export.

## Requirements
- iOS 16+
- LiDAR-capable device for actual scanning (iPhone Pro / iPad Pro)

## Output Files
Scans are stored in the app Documents directory:

- `Documents/RoomScans/<UUID>/room.json`
- `Documents/RoomScans/<UUID>/room.usdz`
- `Documents/RoomScans/<UUID>/room.svg`

## Upload
The app uploads both files together as `multipart/form-data` to:

- `POST http://127.0.0.1:8000/upload`

Parts:
- `scan_id`
- `room_name`
- `room_type`
- `length`
- `width`
- `height`
- `scan_date`
- `device_model`
- `user_id`
- `scan_json` (JSON file)
- `usdz_file` (USDZ file)
- `floorplan_svg` (SVG file)

On a physical device, `127.0.0.1` refers to the device itself. Use your Mac's LAN IP instead (e.g. `http://192.168.1.10:8000/upload`).

## Simulator Notes
RoomPlan scanning does not work in the simulator (no LiDAR / camera). You can still launch the UI and tap the scan button, but the scan will not produce data.

## Run
Open `whc-lidar-ios.xcodeproj` in Xcode and run on a LiDAR device.
