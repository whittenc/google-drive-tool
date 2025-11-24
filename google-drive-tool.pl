#!/usr/bin/perl
use strict;
use warnings;
use 5.010;

use FindBin;
use lib '/programs/cassens/lib';
use lib "$FindBin::Bin/lib";
use Google::Services;
use Getopt::Long;
use Pod::Usage;
use File::Slurp qw(write_file);
use File::Basename qw(basename);
use Term::ReadKey;
use Carp;

sub main {
    my %opts;
    GetOptions(
        \%opts,
        'help|h|?',
        'man',
        'upload',
        'to=s',
        'name=s',
        'notify',
        'overwrite',
        'convert',
        'impersonate=s',
        'debug',
        'setup-credentials',
        'setup-shortcuts',
        'setup-email',
        'get-refresh-token',
        'list-shared',
        'list-shortcuts',
        'add-shortcut=s',
        'remove-shortcut=s',
        'test-folder=s',
        'check-spreadsheet=s',
        'add-tab=s',
        'spreadsheet=s',
        'rows=i',
        'cols=i',
        'append-row=s@',
        'sheet=s',
        'add-header-row=s@',
        'debug-folders',
        'debug-token',
    ) or pod2usage(2);

    # Create Google::Services object with optional impersonation and debug flag
    my %gs_args;
    $gs_args{impersonate_user} = $opts{impersonate} if $opts{impersonate};
    $gs_args{debug} = $opts{debug} if $opts{debug};
    my $gdrive = Google::Services->new(%gs_args);

    pod2usage(1) if $opts{help};
    pod2usage( -exitval => 0, -verbose => 2 ) if $opts{man};

    my $command = find_command(\%opts, \@ARGV);

    if ( $command eq 'setup-credentials' ) {
        cmd_setup_credentials($gdrive);
    }
    elsif ( $command eq 'get-refresh-token' ) {
        cmd_get_refresh_token($gdrive);
    }
    elsif ( $command eq 'list-shared' ) {
        cmd_list_shared($gdrive);
    }
    elsif ( $command eq 'setup-shortcuts' ) {
        cmd_setup_shortcuts($gdrive);
    }
    elsif ( $command eq 'list-shortcuts' ) {
        cmd_list_shortcuts($gdrive);
    }
    elsif ( $command eq 'add-shortcut' ) {
        cmd_add_shortcut( $gdrive, $opts{'add-shortcut'}, $ARGV[0] );
    }
    elsif ( $command eq 'remove-shortcut' ) {
        cmd_remove_shortcut( $gdrive, $opts{'remove-shortcut'} );
    }
    elsif ( $command eq 'setup-email' ) {
        cmd_setup_email($gdrive);
    }
    elsif ( $command eq 'test-folder' ) {
        cmd_test_folder( $gdrive, $opts{'test-folder'} );
    }
    elsif ( $command eq 'check-spreadsheet' ) {
        cmd_check_spreadsheet( $gdrive, $opts{'check-spreadsheet'} );
    }
    elsif ( $command eq 'add-tab' ) {
        cmd_add_tab( $gdrive, $opts{'add-tab'}, $opts{'spreadsheet'}, $opts{rows}, $opts{cols} );
    }
    elsif ( $command eq 'append-row' ) {
        cmd_append_row( $gdrive, $opts{'append-row'}, $opts{'spreadsheet'}, $opts{'sheet'} );
    }
    elsif ( $command eq 'add-header-row' ) {
        cmd_add_header_row( $gdrive, $opts{'add-header-row'}, $opts{'spreadsheet'}, $opts{'sheet'} );
    }
    elsif ( $command eq 'debug-folders' ) {
        cmd_debug_folders($gdrive);
    }
    elsif ( $command eq 'debug-token' ) {
        cmd_debug_token($gdrive);
    }
    elsif ( $command eq 'upload' ) {
        cmd_upload( $gdrive, $opts{to}, $opts{notify}, $opts{overwrite}, $opts{convert}, $ARGV[0], $opts{name} );
    }
    else {
        say "Unknown command. See --help.";
        pod2usage(2);
    }
}

sub find_command {
    my ($opts, $argv) = @_;

    # List of actual commands (not options like 'to', 'spreadsheet', etc.)
    my @command_list = qw(
        upload setup-credentials get-refresh-token list-shared
        setup-shortcuts list-shortcuts add-shortcut remove-shortcut
        setup-email test-folder check-spreadsheet add-tab append-row
        add-header-row debug-folders debug-token
    );

    my @commands = grep { exists $opts->{$_} } @command_list;
    
    # If 'upload' is specified or no other command is given and a file exists
    if ($opts->{upload} || (!@commands && @$argv)) {
        return 'upload';
    }
    return $commands[0] // 'help';
}

sub prompt {
    my ($query, $default) = @_;
    print "$query" . ($default ? " [$default]: " : ": ");
    ReadMode('normal');
    my $input = <STDIN>;
    ReadMode('restore');
    chomp $input;
    return $input || $default;
}

sub cmd_setup_credentials {
    my ($gdrive) = @_;
    say "--- Google API Credential Setup ---";
    my $client_id = prompt("Enter your Client ID");
    my $client_secret = prompt("Enter your Client Secret");
    croak "Client ID and Secret cannot be empty" unless $client_id && $client_secret;
    $gdrive->save_client_credentials($client_id, $client_secret);
    say "Credentials saved. Now run '--get-refresh-token'.";
}

sub cmd_get_refresh_token {
    my ($gdrive) = @_;
    say "--- Generate Google Refresh Token ---";
    my $url = $gdrive->generate_auth_url();
    say "\n1. Visit this URL in your browser:\n\n$url\n";
    say "2. Authorize the application.";
    say "3. You will be redirected to a non-working localhost URL.";
    my $code = prompt("4. Copy the 'code' parameter from that URL and paste it here");
    
    eval {
        my $tokens = $gdrive->exchange_code_for_tokens($code);
        say "\nSuccess! Refresh token has been saved.";
        say "Access Token (expires soon): " . substr($tokens->{access_token}, 0, 30) . "...";
    };
    if ($@) {
        say "\nError: $@";
    }
}

sub cmd_list_shared {
    my ($gdrive) = @_;
    say "--- Listing Shared Folders ---";
    my $folders = $gdrive->list_folders(shared_only => 1);
    if ($folders && @$folders) {
        printf "%-40s %-38s %-25s\n", "Folder Name", "ID", "Owner";
        say "-" x 110;
        for my $f (@$folders) {
            my $owner = $f->{owners}[0]{displayName} // 'Unknown';
            printf "%-40s %-38s %-25s\n", $f->{name}, $f->{id}, $owner;
        }
    } else {
        say "No shared folders found.";
    }
}

sub cmd_setup_shortcuts {
    my ($gdrive) = @_;
    say "--- Interactive Folder Shortcut Setup ---";
    my $folders = $gdrive->list_folders(shared_only => 1);
    my $shortcuts = $gdrive->load_folder_shortcuts();

    unless($folders && @$folders) {
        say "No shared folders found to create shortcuts for.";
        return;
    }

    for my $folder (@$folders) {
        my $owner = $folder->{owners}[0]{displayName} // 'Unknown';
        say "\nFolder: '$folder->{name}' (Owner: $owner)";
        my $shortcut_name = prompt("Enter shortcut name (or press Enter to skip)");
        if ($shortcut_name) {
            $shortcuts->{$shortcut_name} = {
                id => $folder->{id},
                name => $folder->{name},
                owner => $owner,
                created => time()
            };
            say "  Saved shortcut '$shortcut_name'";
        }
    }
    $gdrive->save_folder_shortcuts($shortcuts);
    say "\nShortcuts saved!";
}

sub cmd_list_shortcuts {
    my ($gdrive) = @_;
    say "--- Saved Folder Shortcuts ---";
    my $shortcuts = $gdrive->load_folder_shortcuts();
    if (keys %$shortcuts) {
        printf "%-20s %-40s %-38s\n", "Shortcut", "Folder Name", "ID";
        say "-" x 100;
        for my $s (sort keys %$shortcuts) {
            printf "%-20s %-40s %-38s\n", $s, $shortcuts->{$s}{name}, $shortcuts->{$s}{id};
        }
    } else {
        say "No shortcuts saved. Use --add-shortcut or --setup-shortcuts.";
    }
}

sub cmd_add_shortcut {
    my ($gdrive, $name, $id) = @_;
    croak "Usage: --add-shortcut <name> <folder_id>" unless $name && $id;
    
    my $shortcuts = $gdrive->load_folder_shortcuts();
    my $info = $gdrive->get_file_info($id, 'name,owners');
    croak "Could not find folder with ID $id" unless $info;

    $shortcuts->{$name} = {
        id => $id,
        name => $info->{name},
        owner => $info->{owners}[0]{displayName} // 'Unknown',
        created => time()
    };
    $gdrive->save_folder_shortcuts($shortcuts);
    say "Shortcut '$name' added for folder '$info->{name}'.";
}

sub cmd_remove_shortcut {
    my ($gdrive, $name) = @_;
    croak "Usage: --remove-shortcut <name>" unless $name;
    my $shortcuts = $gdrive->load_folder_shortcuts();
    if (exists $shortcuts->{$name}) {
        delete $shortcuts->{$name};
        $gdrive->save_folder_shortcuts($shortcuts);
        say "Shortcut '$name' removed.";
    } else {
        say "Shortcut '$name' not found.";
    }
}

sub cmd_setup_email {
    my ($gdrive) = @_;
    say "--- Email Notification Setup ---";
    my $config = $gdrive->load_email_config();

    $config->{enabled} = prompt("Enable notifications? (y/n)", $config->{enabled} ? 'y' : 'n') =~ /^y/i;
    if ($config->{enabled}) {
        $config->{sender} = prompt("Sender email (your Gmail)", $config->{sender});
        my $recipients_str = prompt("Recipients (comma-separated)", join(", ", @{$config->{recipients} || []}));
        $config->{recipients} = [ map {s/^\s+|\s+$//g; $_} split /,/, $recipients_str ];
        $config->{subject_template} = prompt("Subject template", $config->{subject_template} || "File Upload: {filename}");
    }
    $gdrive->save_email_config($config);
    say "Email configuration saved.";
}

sub cmd_test_folder {
    my ($gdrive, $id) = @_;
    croak "Usage: --test-folder <folder_id>" unless $id;
    say "--- Testing Access for Folder ID: $id ---";
    
    my $info = $gdrive->get_file_info($id);
    unless ($info) {
        say "FAILED: Could not retrieve folder info. It may not exist or you lack permission.";
        return;
    }
    say "SUCCESS: Folder is accessible.";
    say "  Name: $info->{name}";
    say "  Owner: " . ($info->{owners}[0]{displayName} // 'Unknown');

    if ($info->{mimeType} ne 'application/vnd.google-apps.folder') {
        say "WARNING: This ID is for a file, not a folder.";
        return;
    }

    say "\nTesting upload permission...";
    if ($gdrive->test_folder_upload_permission($id)) {
        say "SUCCESS: You have UPLOAD permission to this folder.";
    } else {
        say "FAILED: You do NOT have upload permission to this folder.";
    }
}

sub cmd_check_spreadsheet {
    my ($gdrive, $id) = @_;
    croak "Usage: --check-spreadsheet <spreadsheet_id>" unless $id;
    say "--- Checking Spreadsheet ID: $id ---";

    my $info = $gdrive->get_file_info($id, 'name,mimeType,owners,webViewLink');
    unless ($info) {
        say "FAILED: Could not retrieve spreadsheet info. It may not exist or you lack permission.";
        return;
    }

    if ($info->{mimeType} ne 'application/vnd.google-apps.spreadsheet' &&
        $info->{mimeType} ne 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        say "FAILED: This ID is not a spreadsheet.";
        say "  Name: $info->{name}";
        say "  Type: $info->{mimeType}";
        return;
    }

    say "SUCCESS: Spreadsheet exists and is accessible.";
    say "  Name: $info->{name}";
    say "  Owner: " . ($info->{owners}[0]{displayName} // 'Unknown');
    say "  Link: $info->{webViewLink}" if $info->{webViewLink};
}

sub cmd_add_tab {
    my ($gdrive, $tab_name, $spreadsheet_id, $rows, $cols) = @_;
    croak "Usage: --add-tab <tab_name> --spreadsheet <spreadsheet_id>" unless $tab_name && $spreadsheet_id;

    say "--- Adding Tab '$tab_name' to Spreadsheet ---";

    # First verify the spreadsheet exists
    my $info = $gdrive->get_file_info($spreadsheet_id, 'name,mimeType');
    unless ($info) {
        say "FAILED: Could not find spreadsheet with ID $spreadsheet_id";
        return;
    }

    if ($info->{mimeType} ne 'application/vnd.google-apps.spreadsheet' &&
        $info->{mimeType} ne 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        say "FAILED: ID $spreadsheet_id is not a spreadsheet";
        return;
    }

    say "Spreadsheet: $info->{name}";

    my %options;
    $options{rows} = $rows if $rows;
    $options{cols} = $cols if $cols;

    my $result = eval { $gdrive->add_spreadsheet_tab($spreadsheet_id, $tab_name, %options) };
    if ($@) {
        say "FAILED: $@";
        return;
    }

    if ($result->{alreadyExists}) {
        say "Tab '$tab_name' already exists (Sheet ID: $result->{sheetId})";
    } else {
        say "SUCCESS: Tab '$tab_name' created";
        if ($result->{replies}[0]{addSheet}{properties}) {
            my $props = $result->{replies}[0]{addSheet}{properties};
            say "  Sheet ID: $props->{sheetId}";
            say "  Rows: $props->{gridProperties}{rowCount}";
            say "  Columns: $props->{gridProperties}{columnCount}";
        }
    }
}

sub cmd_append_row {
    my ($gdrive, $row_data, $spreadsheet_id, $sheet_name) = @_;
    croak "Usage: --append-row <value1> [<value2> ...] --spreadsheet <spreadsheet_id> [--sheet <sheet_name>]"
        unless $row_data && @$row_data && $spreadsheet_id;

    # If only one value provided and it contains commas, split it
    if (@$row_data == 1 && $row_data->[0] =~ /,/) {
        $row_data = [ split(/,/, $row_data->[0]) ];
    }

    $sheet_name ||= 'Sheet1';  # Default to Sheet1 if not specified

    say "--- Appending Row to Spreadsheet ---";

    # First verify the spreadsheet exists
    my $info = $gdrive->get_file_info($spreadsheet_id, 'name,mimeType');
    unless ($info) {
        say "FAILED: Could not find spreadsheet with ID $spreadsheet_id";
        return;
    }

    if ($info->{mimeType} ne 'application/vnd.google-apps.spreadsheet' &&
        $info->{mimeType} ne 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        say "FAILED: ID $spreadsheet_id is not a spreadsheet";
        return;
    }

    say "Spreadsheet: $info->{name}";
    say "Sheet: $sheet_name";
    say "Data: " . join(", ", map { "\"$_\"" } @$row_data);

    # The range is just the sheet name - the API will append to the end
    my $range = $sheet_name;

    my $result = eval { $gdrive->append_spreadsheet_row($spreadsheet_id, $range, $row_data) };
    if ($@) {
        say "FAILED: $@";
        return;
    }

    say "SUCCESS: Row appended";
    if ($result->{updates}) {
        say "  Updated range: $result->{updates}{updatedRange}";
        say "  Rows added: $result->{updates}{updatedRows}";
        say "  Cells updated: $result->{updates}{updatedCells}";
    }
}

sub cmd_add_header_row {
    my ($gdrive, $row_data, $spreadsheet_id, $sheet_name) = @_;
    croak "Usage: --add-header-row <value1> [<value2> ...] --spreadsheet <spreadsheet_id> [--sheet <sheet_name>]"
        unless $row_data && @$row_data && $spreadsheet_id;

    # If only one value provided and it contains commas, split it
    if (@$row_data == 1 && $row_data->[0] =~ /,/) {
        $row_data = [ split(/,/, $row_data->[0]) ];
    }

    $sheet_name ||= 'Sheet1';  # Default to Sheet1 if not specified

    say "--- Adding Header Row to Spreadsheet ---";

    # First verify the spreadsheet exists
    my $info = $gdrive->get_file_info($spreadsheet_id, 'name,mimeType');
    unless ($info) {
        say "FAILED: Could not find spreadsheet with ID $spreadsheet_id";
        return;
    }

    if ($info->{mimeType} ne 'application/vnd.google-apps.spreadsheet' &&
        $info->{mimeType} ne 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        say "FAILED: ID $spreadsheet_id is not a spreadsheet";
        return;
    }

    say "Spreadsheet: $info->{name}";
    say "Sheet: $sheet_name";
    say "Header Data: " . join(", ", map { "\"$_\"" } @$row_data);

    my $result = eval { $gdrive->add_header_row($spreadsheet_id, $sheet_name, $row_data) };
    if ($@) {
        say "FAILED: $@";
        return;
    }

    say "SUCCESS: Header row added with formatting (bold text, gray background)";
    if ($result->{updates}) {
        say "  Updated range: $result->{updates}{updatedRange}";
        say "  Rows added: $result->{updates}{updatedRows}";
        say "  Cells updated: $result->{updates}{updatedCells}";
    }
}

sub cmd_debug_folders {
    my ($gdrive) = @_;
    say "--- Debugging Folder Queries ---";
    say "\n[1] Shared with me:";
    my $shared = $gdrive->list_folders(shared_only => 1);
    for my $f (@$shared) { say "  - $f->{name} (ID: $f->{id})" }

    say "\n[2] Owned by me:";
    my $owned = $gdrive->list_folders(owned_only => 1);
    for my $f (@$owned) { say "  - $f->{name} (ID: $f->{id})" }
}

sub cmd_debug_token {
    my ($gdrive) = @_;
    say "--- Debugging Token ---";
    my $info = $gdrive->check_oauth_scopes();
    if ($info) {
        say "Scope: $info->{scope}";
        say "Audience: $info->{audience}";
        say "Expires in: $info->{expires_in}s";
        say "Token is valid.";
    } else {
        say "Could not validate token.";
    }
}

sub cmd_upload {
    my ($gdrive, $target, $notify, $overwrite, $convert, $file_path, $custom_name) = @_;

    unless ($file_path) {
        say "No file specified for upload. Creating a test file.";
        $file_path = "test_upload_".time().".txt";
        write_file($file_path, "Test file created at ".localtime());
        say "Created '$file_path'.";
    }
    croak "File to upload not found: $file_path" unless -f $file_path;
    croak "No destination folder specified. Use --to <target>" unless $target;

    say "Resolving destination folder '$target'...";
    my $folder_id = $gdrive->resolve_folder_target($target, {
        select_multiple => sub {
            my ($folders) = @_;
            say "Multiple folders found for '$target'. Please choose one:";
            for my $i (0..$#$folders) {
                say "  [$i] $folders->[$i]{name} (ID: $folders->[$i]{id})";
            }
            my $choice = prompt("Enter number", 0);
            return $folders->[$choice]{id};
        },
        not_found => sub {
            croak "Could not find folder matching '$target'.";
        }
    });

    croak "Could not resolve destination folder." unless $folder_id;
    my $folder_info = $gdrive->get_file_info($folder_id, 'name');
    my $folder_name = $folder_info->{name} // $folder_id;

    my $action_verb = $overwrite ? "Uploading (with overwrite)" : "Uploading";
    my ($ext) = $file_path =~ /\.([^.]+)$/;
    if ($convert && lc($ext//'') =~ /^(csv|xls|xlsx)$/i) {
        say "$action_verb and converting '$file_path' to a Google Sheet in '$folder_name'...";
    } else {
        say "$action_verb '$file_path' to '$folder_name'...";
    }

    my $uploaded_file;
    my $upload_action;
    eval { ($uploaded_file, $upload_action) = $gdrive->upload_file_to_drive($file_path, $folder_id, $overwrite, $convert, $custom_name) };
    if ($@) {
        say "\nUPLOAD FAILED: $@";
        exit 1;
    }

    my $success_verb = $upload_action eq 'updated' ? "Updated" : "Uploaded";
    say "File $success_verb successfully!";
    say "  File Name: $uploaded_file->{name}";
    say "  File ID: $uploaded_file->{id}";
    say "  View URL: https://drive.google.com/file/d/$uploaded_file->{id}/view";

    if ($notify) {
        cmd_send_notification($gdrive, $uploaded_file, $folder_id);
    }
}

sub cmd_send_notification {
    my ($gdrive, $uploaded_file, $folder_id) = @_;
    say "\nSending email notifications...";
    
    my $email_config = $gdrive->load_email_config();
    unless ($email_config->{enabled}) {
        say "Email notifications are disabled. Use --setup-email to enable.";
        return;
    }

    my $folder_info = $gdrive->get_file_info($folder_id, 'name');
    my $user_info = $gdrive->get_user_info();

    my $subject = $email_config->{subject_template} || "File Upload: {filename}";
    $subject =~ s/\{filename\}/$uploaded_file->{name}/g;
    $subject =~ s/\{folder\}/$folder_info->{name}/g;

    my $body = "A new file has been uploaded to Google Drive.\n\n"
             . "File: $uploaded_file->{name}\n"
             . "Folder: $folder_info->{name}\n"
             . "Uploader: " . ($user_info->{emailAddress} // 'Unknown') . "\n"
             . "Link: https://drive.google.com/file/d/$uploaded_file->{id}/view\n";

    my $sender = $email_config->{sender}; # Will be undef if not in config
    my $success = 0;
    for my $recipient (@{$email_config->{recipients}}) {
        my $response = $gdrive->send_email_via_gmail($recipient, $subject, $body, $sender);
        if ($response->is_success) {
            say "  -> Sent to $recipient";
            $success++;
        } else {
            say "  -> FAILED to send to $recipient";
            my $error_content = $response->decoded_content;
            my $error_data = eval { JSON->new->decode($error_content) };
            if ($error_data && $error_data->{error}{message}) {
                say "     Error: " . $error_data->{error}{message};
            } else {
                say "     Error: " . $response->status_line;
            }
        }
    }
    say "Sent $success notifications.";
}

main();

__END__

=head1 NAME

gdrive-tool.pl - A command-line tool for Google Drive uploads and management.

=head1 SYNOPSIS

gdrive-tool.pl --upload [options] <file_to_upload>
gdrive-tool.pl <command> [options]

=head1 DESCRIPTION

This script provides a comprehensive command-line interface for interacting with Google Drive. It can upload files, manage folder shortcuts, and send email notifications.

=head1 COMMANDS

=over 4

=item B<--upload>

Uploads a file. This is the default action if a file path is provided as an argument.

=item B<--setup-credentials>

Interactively prompts for your Google API Client ID and Secret. This is the first step for new users.

=item B<--get-refresh-token>

Guides you through the OAuth2 flow to generate a refresh token, which is necessary for authentication. Run this after setting credentials.

=item B<--list-shared>

Lists all folders that have been shared with you on Google Drive.

=item B<--setup-shortcuts>

Starts an interactive session to create named shortcuts for your shared folders, making uploads easier.

=item B<--list-shortcuts>

Displays all currently saved folder shortcuts.

=item B<--add-shortcut> I<name> I<folder_id>

Manually adds a new shortcut.

=item B<--remove-shortcut> I<name>

Removes a previously saved shortcut.

=item B<--setup-email>

Configures settings for sending email notifications after a successful upload.

=item B<--test-folder> I<folder_id>

Checks if a given folder ID is accessible and if you have upload permissions.

=item B<--check-spreadsheet> I<spreadsheet_id>

Checks if a given spreadsheet ID exists and is accessible. Verifies that the ID points to a valid Google Sheets spreadsheet.

=item B<--add-tab> I<tab_name> B<--spreadsheet> I<spreadsheet_id> [B<--rows> I<n>] [B<--cols> I<n>]

Adds a new tab (sheet) to an existing Google Sheets spreadsheet. If a tab with the same name already exists, reports that fact without creating a duplicate. Optional --rows and --cols parameters specify the size of the new tab (defaults: 1000 rows, 26 columns).

=item B<--append-row> I<value1> [I<value2> ...] B<--spreadsheet> I<spreadsheet_id> [B<--sheet> I<sheet_name>]

Appends a row of data to the end of a spreadsheet. Provide multiple --append-row arguments for multiple column values. The --sheet parameter specifies which tab/sheet to append to (defaults to 'Sheet1').

=item B<--add-header-row> I<value1> [I<value2> ...] B<--spreadsheet> I<spreadsheet_id> [B<--sheet> I<sheet_name>]

Adds a formatted header row to the first row of a spreadsheet. The header will have bold text and a gray background. Provide multiple --add-header-row arguments for multiple column headers. The --sheet parameter specifies which tab/sheet to add the header to (defaults to 'Sheet1').

=item B<--debug-folders>

Runs diagnostic queries to list shared and owned folders.

=item B<--debug-token>

Checks the validity and scopes of your current access token.

=item B<--help|?>, B<--man>

Shows help and documentation.

=back

=head1 UPLOAD OPTIONS

=over 4

=item B<--to> I<target>

(Required for upload) Specifies the destination folder. The target can be a folder ID, a saved shortcut name, a full folder path (e.g., 'Root/Subfolder'), or a folder name.

=item B<--name> I<filename>

Specifies a custom filename for the uploaded file. If not provided, the original filename will be used. Note: When using C<--convert> with this option, the file will be uploaded with the custom name (without the original extension for converted files).

=item B<--notify>

If specified, sends an email notification after a successful upload, using the settings from C<--setup-email>.

=item B<--overwrite>

If a file with the same name already exists in the destination folder, its content will be updated. Otherwise, Google Drive will create a new file with a duplicate name.

=item B<--convert>

If uploading a CSV, XLS, or XLSX file, convert it to a native Google Sheet. The resulting file will have the same name, but without the file extension. When used with C<--overwrite>, it will look for an existing Google Sheet with the converted name to update.

=item B<--impersonate> I<email>

(Service Account only) When using service account authentication, impersonate the specified user. All operations will be performed as that user. This requires domain-wide delegation to be enabled for the service account in Google Workspace Admin Console.

Example: C<--impersonate user@example.com>

=back

=head1 EXAMPLES

=over 4

=item First-time setup:

  gdrive-tool.pl --setup-credentials
  gdrive-tool.pl --get-refresh-token
  gdrive-tool.pl --setup-shortcuts

=item Upload a file to a shortcut named 'reports':

  gdrive-tool.pl --upload --to reports monthly.csv

=item Upload a file with a custom filename:

  gdrive-tool.pl --upload --to reports --name "2025-Q1-Report.csv" monthly.csv

=item Upload with an email notification:

  gdrive-tool.pl --upload --to reports --notify monthly.csv

=item Upload and overwrite an existing file:

  gdrive-tool.pl --upload --to reports --overwrite daily_status.txt

=item Upload and convert a spreadsheet to a Google Sheet:

  gdrive-tool.pl --upload --to reports --convert sales.xlsx

=item Upload and convert a spreadsheet with a custom name:

  gdrive-tool.pl --upload --to reports --convert --name "Q1 Sales Report" sales.xlsx

=item List your shortcuts:

  gdrive-tool.pl --list-shortcuts

=item Test access to a folder:

  gdrive-tool.pl --test-folder 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs

=item Check if a spreadsheet exists:

  gdrive-tool.pl --check-spreadsheet 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs

=item Add a new tab to a spreadsheet:

  gdrive-tool.pl --add-tab "Monthly Report" --spreadsheet 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs

=item Add a tab with custom size:

  gdrive-tool.pl --add-tab "Data" --spreadsheet 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs --rows 5000 --cols 50

=item Append a row to the default sheet (Sheet1):

  gdrive-tool.pl --append-row "John Doe" --append-row "john@example.com" --append-row "555-1234" --spreadsheet 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs

=item Append a row to a specific sheet:

  gdrive-tool.pl --append-row "2025-01-15" --append-row "Revenue" --append-row "5000" --spreadsheet 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs --sheet "Monthly Report"

=item Add a formatted header row:

  gdrive-tool.pl --add-header-row "Name" --add-header-row "Email" --add-header-row "Phone" --spreadsheet 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs --sheet "Contacts"

=back

=cut
