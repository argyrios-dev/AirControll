# Security Policy

## Supported version

Security fixes are accepted for AirControll 0.1.x.

## Reporting a vulnerability

Please report vulnerabilities privately to Argyrios, the project creator. Include the affected version, macOS version, reproduction steps, and impact. Do not include camera recordings; AirControll never creates them.

## Privacy and security design

AirControll has no networking, analytics, telemetry, advertising, cloud processing, or remote logging. Camera frames are processed locally in memory and are not saved. Persisted gesture data contains only normalized numeric features and aggregate statistics. Application bookmarks are stored only when the user explicitly selects an application.
