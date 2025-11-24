# Service Account Impersonation Example

## What is User Impersonation?

When using a service account with domain-wide delegation, you can have the service account "impersonate" (act as) a specific user in your Google Workspace organization. This means:

- Files will appear to be uploaded by that user
- The user's permissions and folder access apply
- Audit logs show the impersonated user as the actor
- The service account itself doesn't need direct access to folders

## Setup Requirements

### 1. Service Account Configuration

Your service account JSON file should be placed at:
- `/data/cassens/lib/Google/.google_credentials/perl-drive-upload-56687a459f35.json`
- OR in the project root as `perl-drive-upload-56687a459f35.json`

### 2. Enable Domain-Wide Delegation

In Google Workspace Admin Console (admin.google.com):

1. **Navigate to Security:**
   - Security > Access and data control > API controls > Domain-wide delegation

2. **Add a new API client:**
   - Client ID: `108225560226222991978` (from your service account JSON)
   - OAuth Scope:
     ```
     https://www.googleapis.com/auth/drive.file
     ```
   - **Important**: This scope limits access to only files created or opened by the app

3. **Authorize** the client

### 3. User Must Exist

The email you're impersonating must be a valid user in your Google Workspace domain.

## Usage Examples

### Without Impersonation (Service Account Identity)
```bash
# Files uploaded as: 420588204332-compute@developer.gserviceaccount.com
perl google-drive-tool.pl --upload --to "My Folder" report.xlsx
```

### With Impersonation (As Specific User)
```bash
# Files uploaded as: john.doe@example.com
perl google-drive-tool.pl --upload --to "My Folder" --impersonate john.doe@example.com report.xlsx
```

### List Folders as Impersonated User
```bash
# Shows folders accessible to jane.smith@example.com
perl google-drive-tool.pl --list-shared --impersonate jane.smith@example.com
```

### With Notifications
```bash
# Upload and notify as the impersonated user
perl google-drive-tool.pl --upload --to "Reports" \
  --impersonate accounting@example.com \
  --notify \
  monthly_report.csv
```

## Benefits

1. **Proper Attribution**: Files show the correct owner/uploader
2. **Audit Trail**: Activity logs reflect actual user actions
3. **Permission Inheritance**: Uses the impersonated user's folder access
4. **No Sharing Required**: Service account doesn't need folder access
5. **Centralized Auth**: One service account can act as many users

## Troubleshooting

### "Invalid email or User ID" Error
- Domain-wide delegation not configured
- Client ID not authorized
- Scopes not matching
- User doesn't exist in the domain

### "Access Denied" Errors
- Impersonated user lacks access to target folder
- Service account scopes insufficient
- Admin hasn't approved delegation

### How to Test
```bash
# Test without impersonation first
perl google-drive-tool.pl --list-shared

# Then test with impersonation
perl google-drive-tool.pl --list-shared --impersonate user@yourdomain.com
```

## Security Notes

- Service account has powerful capabilities
- Protect the JSON key file (permissions 600)
- Limit who can run the tool
- Monitor service account usage in Admin Console
- Consider separate service accounts for different use cases
