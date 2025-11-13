# System Administrator Guide: Google Drive Tool

This guide provides system administrators with essential information for deploying, securing, and maintaining the Google Drive command-line tool.

## Prerequisites

### System Requirements
- Perl 5.010 or higher
- Internet connectivity for Google API access
- File system permissions to create/modify files in the tool directory

### Required Perl Modules
```bash
# Core modules (usually included with Perl)
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use File::Spec;
use Cwd;

# Additional CPAN modules required
cpan install JSON
cpan install LWP::UserAgent
cpan install File::Slurp
cpan install Term::ReadKey
cpan install MIME::Base64
cpan install URI::Escape
```

## Security Considerations

### File Permissions
The tool automatically creates `.google_credentials/` with restrictive permissions:
- Directory: 755 (readable/executable by owner and group)
- Credential files: 600 (readable/writable by owner only)

**Critical Files to Secure:**
- `.google_credentials/client_id.txt` - Google API Client ID
- `.google_credentials/client_secret.txt` - Google API Client Secret  
- `.google_credentials/refresh_token.txt` - OAuth2 refresh token
- `.google_credentials/email_notifications.json` - Email configuration
- `.google_credentials/folders.json` - Folder shortcuts

### Network Security
- Tool communicates with:
  - `https://oauth2.googleapis.com` (OAuth2 endpoints)
  - `https://www.googleapis.com` (Drive and Gmail APIs)
- Uses HTTPS only for all API communications
- No local network services or ports opened

### Authentication Security
- Uses OAuth2 with refresh tokens (no password storage)
- Tokens automatically refresh on expiration
- Client credentials must be obtained from Google Cloud Console
- Scopes limited to Drive access and Gmail send

## Deployment

### Single User Installation
```bash
# 1. Copy tool files
cp google-drive-tool.pl /usr/local/bin/
cp -r lib/ /usr/local/lib/perl5/
chmod +x /usr/local/bin/google-drive-tool.pl

# 2. Create credentials directory (done automatically on first run)
# 3. User runs initial setup commands
```

### Multi-User Environment
```bash
# Option 1: System-wide installation with user-specific credentials
cp google-drive-tool.pl /usr/local/bin/
cp -r lib/ /usr/local/lib/perl5/
# Each user maintains their own .google_credentials/ in their working directory

# Option 2: Shared service account (advanced)
# Requires service account key and different authentication flow
```

## Google Cloud Console Setup

### Required API Configuration
1. **Enable APIs:**
   - Google Drive API
   - Gmail API (if using email notifications)

2. **Create OAuth2 Credentials:**
   - Application Type: Desktop Application
   - Authorized Redirect URI: `http://localhost:9090/oauth/callback`

3. **Required Scopes:**
   - `https://www.googleapis.com/auth/drive` (file management)
   - `https://www.googleapis.com/auth/gmail.send` (notifications)

### Service Account Alternative (Advanced)
For automated/unattended usage, consider service accounts:
- Download service account JSON key
- Modify authentication flow in `Google::Services.pm`
- Share target folders with service account email

## Configuration Management

### Initial Setup Process
```bash
# 1. Set credentials
./google-drive-tool.pl --setup-credentials

# 2. Complete OAuth2 flow
./google-drive-tool.pl --get-refresh-token

# 3. Configure folder shortcuts
./google-drive-tool.pl --setup-shortcuts

# 4. Configure email notifications (optional)
./google-drive-tool.pl --setup-email
```

### Configuration Files
- **client_id.txt**: Google API Client ID (plain text)
- **client_secret.txt**: Google API Client Secret (plain text)
- **refresh_token.txt**: OAuth2 refresh token (plain text)
- **folders.json**: Folder shortcuts mapping (JSON format)
- **email_notifications.json**: Email settings (JSON format)

## Monitoring and Logging

### Error Handling
- Tool uses `croak` for fatal errors
- No built-in logging mechanism
- Errors printed to STDERR

### Recommended Logging Setup
```bash
# Wrapper script for logging
#!/bin/bash
LOG_FILE="/var/log/google-drive-tool.log"
echo "$(date): $@" >> "$LOG_FILE"
perl /usr/local/bin/google-drive-tool.pl "$@" 2>&1 | tee -a "$LOG_FILE"
```

### Health Checks
```bash
# Test authentication and permissions
./google-drive-tool.pl --debug-token

# Test folder access
./google-drive-tool.pl --test-folder <folder_id>

# List accessible folders
./google-drive-tool.pl --list-shared
```

## Backup and Recovery

### Critical Data to Backup
- `.google_credentials/` directory (entire contents)
- Any custom configuration files
- Folder shortcut mappings

### Recovery Process
1. Restore `.google_credentials/` directory
2. Verify file permissions (600 for credential files)
3. Test authentication: `./google-drive-tool.pl --debug-token`
4. If refresh token expired, re-run OAuth2 flow

## Common Administrative Tasks

### Adding New Users
1. Provide access to tool executable
2. User runs initial setup process
3. Share target folders with user's Google account
4. Configure folder shortcuts for common destinations

### Troubleshooting Access Issues
```bash
# Check token validity
./google-drive-tool.pl --debug-token

# Test specific folder access
./google-drive-tool.pl --test-folder <folder_id>

# Debug folder permissions
./google-drive-tool.pl --debug-folders
```

### Updating API Credentials
1. Update Client ID/Secret in Google Cloud Console
2. Run: `./google-drive-tool.pl --setup-credentials`
3. Re-authenticate: `./google-drive-tool.pl --get-refresh-token`

## Performance Considerations

### File Upload Limits
- Google Drive API rate limits apply
- Large file uploads may timeout (default: 120 seconds)
- Consider chunked uploads for files > 5MB (not currently implemented)

### Concurrent Usage
- Tool not designed for high concurrency
- Each instance maintains separate token state
- Consider queuing mechanism for batch operations

## Security Incident Response

### Credential Compromise
1. **Immediate Actions:**
   - Revoke tokens in Google Cloud Console
   - Delete local credential files
   - Change Client Secret if necessary

2. **Recovery:**
   - Generate new credentials
   - Re-run setup process
   - Update any automated scripts

### Audit Logging
- Google Cloud Console provides API usage logs
- Drive activity logs show file operations
- Gmail API logs show notification activity

## Maintenance

### Regular Tasks
- Monitor Google Cloud Console for API usage/quotas
- Review and rotate credentials periodically
- Update Perl modules as needed
- Test authentication flow quarterly
