# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Perl-based command-line tool for Google Drive file management and uploads. The tool provides OAuth2 authentication, file uploading with conversion options, folder shortcut management, and email notifications.

## Architecture

- **Main Script**: `google-drive-tool.pl` - Command-line interface with POD documentation
- **Core Module**: `lib/Google/Services.pm` - Google Drive and Gmail API wrapper
- **Configuration**: `.google_credentials/` directory stores:
  - OAuth2 credentials (`client_id.txt`, `client_secret.txt`, `refresh_token.txt`)
  - Folder shortcuts (`folders.json`) 
  - Email notification settings (`email_notifications.json`)

## Key Components

### Authentication Flow
- Uses OAuth2 with refresh tokens for persistent authentication
- Automatic token refresh on 401 responses in `_api_request()` method
- Scopes: Google Drive API and Gmail Send API

### File Upload System
- Supports file uploads to Google Drive folders
- Optional conversion of CSV/XLS/XLSX files to Google Sheets
- Overwrite detection and handling
- Upload permission testing via `test_folder_upload_permission()`

### Folder Management
- Folder resolution system supports:
  - Direct folder IDs
  - Named shortcuts
  - Folder paths (e.g., 'Root/Subfolder')
  - Folder name matching with conflict resolution
- Folder queries distinguish between shared and owned folders

### Notification System
- Gmail API integration for upload notifications
- Template-based email subjects with placeholders (`{filename}`, `{folder}`)
- Multi-recipient support

## Running the Tool

The main executable is `google-drive-tool.pl`. Key usage patterns:

### Initial Setup
```bash
perl google-drive-tool.pl --setup-credentials
perl google-drive-tool.pl --get-refresh-token
perl google-drive-tool.pl --setup-shortcuts
```

### File Upload
```bash
perl google-drive-tool.pl --upload --to <target> [options] <file>
```

### Folder Management
```bash
perl google-drive-tool.pl --list-shared
perl google-drive-tool.pl --list-shortcuts  
perl google-drive-tool.pl --test-folder <folder_id>
```

## Development Notes

- Uses modern Perl (5.010+) with strict/warnings
- Configuration files are stored with restrictive permissions (600)
- Error handling uses `croak` for user-facing errors
- POD documentation is embedded in the main script
- No external test framework - manual testing recommended via `--test-folder`