package Google::Services;

use strict;
use warnings;
use 5.010;
use File::Basename;
use File::Slurp qw(read_file write_file);
use File::Spec;
use Cwd qw(abs_path);
use Carp;
use Data::Dumper;
use Encode;
use JSON;
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64 decode_base64);
use URI::Escape qw(uri_escape);
use File::Temp qw(tempfile);

our $VERSION = '1.0.0';

# --- Configuration ---
my $DEFAULT_CREDENTIALS_DIR = '/data/cassens/lib/Google/.google_credentials';
my $CLIENT_ID_FILE        = "client_id.txt";
my $CLIENT_SECRET_FILE    = "client_secret.txt";
my $REFRESH_TOKEN_FILE    = "refresh_token.txt";
my $SERVICE_ACCOUNT_FILE  = "/data/cassens/lib/Google/.google_credentials/perl-drive-upload-56687a459f35.json";
my $FOLDERS_CONFIG_FILE   = "folders.json";
my $EMAIL_CONFIG_FILE     = "email_notifications.json";
my $REDIRECT_URI          = 'http://localhost:9090/oauth/callback';
my $SCOPE                 = 'https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/gmail.send';

sub new {
    my ( $class, %args ) = @_;

    my $self = {
        credentials_dir       => $args{credentials_dir} || $DEFAULT_CREDENTIALS_DIR,
        service_account_file  => $args{service_account_file},
        impersonate_user      => $args{impersonate_user},
        client_id             => undef,
        client_secret         => undef,
        refresh_token         => undef,
        access_token          => undef,
        # Service account fields
        service_account_email => undef,
        private_key           => undef,
        use_service_account   => 0,
        ua                    => LWP::UserAgent->new( timeout => 120 ),
        json                  => JSON->new->allow_nonref->pretty,
    };

    bless $self, $class;

    mkdir $self->{credentials_dir} unless -d $self->{credentials_dir};

    # Try to load service account credentials first
    $self->_load_service_account_credentials();

    # Fall back to OAuth2 if service account not available
    $self->_load_credentials() unless $self->{use_service_account};

    return $self;
}


sub _get_config_path {
    my ( $self, $filename ) = @_;
    return File::Spec->catfile( $self->{credentials_dir}, $filename );
}

sub _read_config_file {
    my ( $self, $path ) = @_;
    return unless -f $path;
    my $content = eval { read_file( $path, { chomp => 1 } ) };
    croak "Could not read file $path: $@" if $@;
    $content =~ s/^\s+|\s+$//g;
    return $content;
}

sub _load_credentials {
    my ($self) = @_;
    my $client_id_path     = $self->_get_config_path($CLIENT_ID_FILE);
    my $client_secret_path = $self->_get_config_path($CLIENT_SECRET_FILE);
    my $refresh_token_path = $self->_get_config_path($REFRESH_TOKEN_FILE);

    $self->{client_id}     = $self->_read_config_file($client_id_path)     if -f $client_id_path;
    $self->{client_secret} = $self->_read_config_file($client_secret_path) if -f $client_secret_path;
    $self->{refresh_token} = $self->_read_config_file($refresh_token_path) if -f $refresh_token_path;
}

sub _load_service_account_credentials {
    my ($self) = @_;

    # Determine the service account file path
    my $sa_file = $self->{service_account_file};

    # If not provided, use the default SERVICE_ACCOUNT_FILE constant
    unless ($sa_file) {
        $sa_file = $SERVICE_ACCOUNT_FILE;
    }

    warn "DEBUG: Checking for service account file at: $sa_file\n";
    unless (-f $sa_file) {
        warn "DEBUG: Service account file not found\n";
        return;
    }
    warn "DEBUG: Service account file found\n";

    # Read and parse the service account JSON
    my $content = eval { read_file($sa_file) };
    if ($@) {
        warn "DEBUG: Failed to read service account file: $@\n";
        return;
    }

    my $sa_data = eval { $self->{json}->decode($content) };
    if ($@ || !$sa_data) {
        warn "DEBUG: Failed to parse service account JSON: $@\n";
        return;
    }

    # Verify it's a service account file
    unless ($sa_data->{type} && $sa_data->{type} eq 'service_account') {
        warn "DEBUG: File is not a service account (type: " . ($sa_data->{type} // 'undefined') . ")\n";
        return;
    }
    unless ($sa_data->{private_key} && $sa_data->{client_email}) {
        warn "DEBUG: Service account file missing required fields\n";
        return;
    }

    # Store service account credentials
    $self->{service_account_email} = $sa_data->{client_email};
    $self->{private_key} = $sa_data->{private_key};
    $self->{use_service_account} = 1;

    warn "DEBUG: Service account credentials loaded successfully (email: $self->{service_account_email})\n";
    return 1;
}

sub _api_request {
    my ( $self, $request ) = @_;

    # Ensure we have an access token
    $self->get_access_token() unless $self->{access_token};
    $request->header( Authorization => "Bearer " . $self->{access_token} );

    my $response = $self->{ua}->request($request);

    # Simple token refresh logic on 401 Unauthorized
    if ( $response->code == 401 ) {
        $self->{access_token} = undef;    # Force refresh
        $self->get_access_token();

        # Retry request with new token
        $request->header( Authorization => "Bearer " . $self->{access_token} );
        $response = $self->{ua}->request($request);
    }

    return $response;
}

sub _load_json_config {
    my ( $self, $file ) = @_;
    my $path = $self->_get_config_path($file);
    return {} unless -f $path;

    my $content = eval { read_file($path) };
    croak "Error reading config file $path: $@" if $@;

    $content =~ s/^\x{FEFF}//;    # Remove UTF-8 BOM
    $content =~ s/^\s+|\s+$//g;
    return {} unless $content;

    my $data = eval { $self->{json}->decode($content) };
    croak "Error parsing JSON in $path: $@" if $@;

    return $data;
}

sub _save_json_config {
    my ( $self, $file, $data ) = @_;
    my $path = $self->_get_config_path($file);
    eval {
        write_file( $path, $self->{json}->encode($data) );
        chmod 0600, $path;
    };
    croak "Could not save config to $path: $@" if $@;
    return 1;
}

sub _base64url_encode {
    my ($data) = @_;
    my $encoded = encode_base64($data, '');
    $encoded =~ s/\+/-/g;
    $encoded =~ s/\//_/g;
    $encoded =~ s/=+$//;
    return $encoded;
}

sub _create_jwt {
    my ($self) = @_;

    croak "Service account credentials not loaded"
      unless $self->{use_service_account} && $self->{private_key} && $self->{service_account_email};

    my $now = time();
    my $exp = $now + 3600;  # Token valid for 1 hour

    # JWT Header
    my $header = {
        alg => "RS256",
        typ => "JWT"
    };

    # JWT Payload (Claims)
    my $payload = {
        iss   => $self->{service_account_email},
        scope => $SCOPE,
        aud   => "https://oauth2.googleapis.com/token",
        exp   => $exp,
        iat   => $now
    };

    # Add impersonation if specified
    if ($self->{impersonate_user}) {
        $payload->{sub} = $self->{impersonate_user};
    }

    # Encode header and payload (use canonical/compact encoding)
    my $json_encoder = JSON->new->canonical;
    my $header_json = $json_encoder->encode($header);
    my $payload_json = $json_encoder->encode($payload);

    my $header_b64 = _base64url_encode($header_json);
    my $payload_b64 = _base64url_encode($payload_json);

    my $signing_input = "$header_b64.$payload_b64";

    # Sign with RSA private key using openssl command
    # Create temporary file for private key
    my ($key_fh, $key_filename) = tempfile(UNLINK => 1);
    print $key_fh $self->{private_key};
    close $key_fh;

    # Sign using openssl
    my $signature = `echo -n "$signing_input" | openssl dgst -sha256 -sign "$key_filename" -binary`;
    croak "OpenSSL signing failed: $!" if $?;

    my $signature_b64 = _base64url_encode($signature);

    # Clean up temp file
    unlink $key_filename;

    return "$signing_input.$signature_b64";
}

sub _get_service_account_token {
    my ($self) = @_;

    my $jwt = $self->_create_jwt();

    my $response = $self->{ua}->post(
        'https://oauth2.googleapis.com/token',
        Content => [
            grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion  => $jwt
        ]
    );

    croak "Service account token request failed: " . $response->decoded_content
      unless $response->is_success;

    my $data = $self->{json}->decode($response->decoded_content);

    # Google may return either access_token or id_token depending on the request
    # For service accounts, we can use id_token as an access token
    return $data->{access_token} || $data->{id_token};
}

sub get_access_token {
    my ($self) = @_;
    return $self->{access_token} if $self->{access_token};

    # Use service account authentication if available
    if ($self->{use_service_account}) {
        warn "DEBUG: Using service account authentication (email: $self->{service_account_email})\n";
        $self->{access_token} = $self->_get_service_account_token();
        return $self->{access_token};
    }

    # Otherwise use OAuth2 refresh token flow
    croak "Credentials not configured. Run setup."
      unless $self->{client_id} && $self->{client_secret} && $self->{refresh_token};

    my $response = $self->{ua}->post(
        'https://oauth2.googleapis.com/token',
        Content => [
            client_id     => $self->{client_id},
            client_secret => $self->{client_secret},
            refresh_token => $self->{refresh_token},
            grant_type    => 'refresh_token'
        ]
    );

    croak "Token refresh failed: " . $response->decoded_content
      unless $response->is_success;

    my $data = $self->{json}->decode( $response->decoded_content );
    $self->{access_token} = $data->{access_token};
    return $self->{access_token};
}

sub save_client_credentials {
    my ( $self, $client_id, $client_secret ) = @_;
    my $id_path     = $self->_get_config_path($CLIENT_ID_FILE);
    my $secret_path = $self->_get_config_path($CLIENT_SECRET_FILE);
    write_file( $id_path,     $client_id );
    write_file( $secret_path, $client_secret );
    chmod 0600, $id_path;
    chmod 0600, $secret_path;
    $self->_load_credentials();
}

sub generate_auth_url {
    my ($self) = @_;
    croak "Client ID not configured." unless $self->{client_id};

    my $auth_url =
        "https://accounts.google.com/o/oauth2/v2/auth?"
      . "client_id=" . uri_escape( $self->{client_id} )
      . "&redirect_uri=" . uri_escape($REDIRECT_URI)
      . "&scope=" . uri_escape($SCOPE)
      . "&response_type=code"
      . "&access_type=offline"
      . "&prompt=consent";

    return $auth_url;
}

sub exchange_code_for_tokens {
    my ( $self, $auth_code ) = @_;
    croak "Client ID/Secret not configured."
      unless $self->{client_id} && $self->{client_secret};

    my $response = $self->{ua}->post(
        'https://oauth2.googleapis.com/token',
        Content => [
            client_id     => $self->{client_id},
            client_secret => $self->{client_secret},
            redirect_uri  => $REDIRECT_URI,
            grant_type    => 'authorization_code',
            code          => $auth_code
        ]
    );

    croak "Token exchange failed: " . $response->decoded_content
      unless $response->is_success;

    my $data = $self->{json}->decode( $response->decoded_content );
    if ( $data->{refresh_token} ) {
        $self->save_refresh_token( $data->{refresh_token} );
    }
    return $data;
}

sub save_refresh_token {
    my ( $self, $refresh_token ) = @_;
    my $path = $self->_get_config_path($REFRESH_TOKEN_FILE);
    write_file( $path, $refresh_token );
    chmod 0600, $path;
    $self->{refresh_token} = $refresh_token;
}

sub load_folder_shortcuts {
    my ($self) = @_;
    my $shortcuts = $self->_load_json_config($FOLDERS_CONFIG_FILE);
    return ref($shortcuts) eq 'HASH' ? $shortcuts : {};
}

sub save_folder_shortcuts {
    my ( $self, $shortcuts ) = @_;
    return $self->_save_json_config( $FOLDERS_CONFIG_FILE, $shortcuts );
}

sub load_email_config {
    my ($self) = @_;
    my $config = $self->_load_json_config($EMAIL_CONFIG_FILE);
    return ref($config) eq 'HASH' ? $config : {};
}

sub save_email_config {
    my ( $self, $config ) = @_;
    return $self->_save_json_config( $EMAIL_CONFIG_FILE, $config );
}

sub search_folder_by_name {
    my ( $self, $folder_name, $parent_id ) = @_;

    my $query =
      "mimeType='application/vnd.google-apps.folder' and name='$folder_name' and trashed=false";
    $query .= " and '$parent_id' in parents" if $parent_id;

    my $url =
        'https://www.googleapis.com/drive/v3/files?'
      . 'q=' . uri_escape($query)
      . '&fields=files(id,name,parents,permissions,owners)&supportsAllDrives=true';

    my $req      = HTTP::Request->new( GET => $url );
    my $response = $self->_api_request($req);

    return unless $response->is_success;
    return $self->{json}->decode( $response->decoded_content )->{files};
}

sub get_folder_id_by_path {
    my ( $self, $folder_path, $callbacks ) = @_;
    $callbacks //= {};

    $folder_path =~ s|^/||;
    $folder_path =~ s|/$||;
    my @path_parts = split '/', $folder_path;

    my $current_parent_id = undef;

    for my $folder_name (@path_parts) {
        my $folders =
          $self->search_folder_by_name( $folder_name, $current_parent_id );

        if ( !$folders || @$folders == 0 ) {
            $callbacks->{not_found}->( $folder_name, $current_parent_id )
              if $callbacks->{not_found};
            return undef;
        }
        elsif ( @$folders > 1 ) {
            $callbacks->{multiple_found}->($folders) if $callbacks->{multiple_found};
        }

        $current_parent_id = $folders->[0]->{id};
        $callbacks->{found}->( $folder_name, $current_parent_id )
          if $callbacks->{found};
    }

    return $current_parent_id;
}

sub list_folders {
    my ( $self, %params ) = @_;
    my $shared_only = $params{shared_only};
    my $owned_only  = $params{owned_only};

    my $query = "mimeType='application/vnd.google-apps.folder' and trashed=false";
    $query .= " and sharedWithMe=true" if $shared_only;
    $query .= " and 'me' in owners"    if $owned_only;

    my $url =
        'https://www.googleapis.com/drive/v3/files?'
      . 'q=' . uri_escape($query)
      . '&fields=files(id,name,owners,permissions,shared)'
      . '&pageSize=200&supportsAllDrives=true';

    my $req      = HTTP::Request->new( GET => $url );
    my $response = $self->_api_request($req);

    return unless $response->is_success;
    return $self->{json}->decode( $response->decoded_content )->{files};
}

sub resolve_folder_target {
    my ( $self, $target, $callbacks ) = @_;
    $callbacks //= {};

    return undef unless $target;

    if ( $target =~ /^[a-zA-Z0-9_-]{20,}$/ ) {
        $callbacks->{resolved}->( "ID", $target, $target ) if $callbacks->{resolved};
        return $target;
    }

    my $shortcuts = $self->load_folder_shortcuts();
    if ( exists $shortcuts->{$target} ) {
        my $info = $shortcuts->{$target};
        if ( ref($info) eq 'HASH' && $info->{id} ) {
            $callbacks->{resolved}->( "Shortcut", $target, $info->{id} )
              if $callbacks->{resolved};
            return $info->{id};
        }
    }

    if ( $target =~ m|/| ) {
        return $self->get_folder_id_by_path( $target, $callbacks->{path_resolver} );
    }

    my $folders = $self->search_folder_by_name($target);
    if ( !$folders || @$folders == 0 ) {
        $callbacks->{not_found}->($target) if $callbacks->{not_found};
        return undef;
    }

    if ( @$folders > 1 ) {
        if ( $callbacks->{select_multiple} ) {
            return $callbacks->{select_multiple}->($folders);
        }
    }

    my $folder_id = $folders->[0]->{id};
    $callbacks->{resolved}->( "Name Search", $target, $folder_id )
      if $callbacks->{resolved};
    return $folder_id;
}

sub search_file_by_name_in_folder {
    my ( $self, $filename, $folder_id ) = @_;

    my $escaped_filename = $filename;
    $escaped_filename =~ s/'/\\'/g;

    my $query =
      "name = '$escaped_filename' and '$folder_id' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed=false";

    my $url =
        'https://www.googleapis.com/drive/v3/files?'
      . 'q=' . uri_escape($query)
      . '&fields=files(id,name)&supportsAllDrives=true&includeItemsFromAllDrives=true';

    my $req      = HTTP::Request->new( GET => $url );
    my $response = $self->_api_request($req);

    return unless $response->is_success;
    my $data = $self->{json}->decode( $response->decoded_content );
    my $files = $data->{files};

    # Return the first file found
    return $files->[0] if ( $files && @$files > 0 );
    return undef;
}

sub upload_file_to_drive {
    my ( $self, $file_path, $folder_id, $overwrite, $convert, $custom_name ) = @_;

    croak "File not found: $file_path" unless -f $file_path;

    # Get the original filename and extract its extension
    my $original_filename = basename($file_path);
    my ( $original_basename, $ext ) = $original_filename =~ /^(.*)\.([^.]+)$/;
    $ext //= '';
    $original_basename //= $original_filename;

    # Use custom name if provided, otherwise use original
    my $file_basename = $custom_name || $original_basename;
    my $filename = $custom_name ? ($custom_name =~ /\./ ? $custom_name : "$custom_name.$ext") : $original_filename;

    my %mime_types = (
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'xls'  => 'application/vnd.ms-excel',
        'csv'  => 'text/csv',
        'ods'  => 'application/vnd.oasis.opendocument.spreadsheet',
        'txt'  => 'text/plain',
        'pdf'  => 'application/pdf',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    );

    my $mime_type = $mime_types{ lc($ext) } || 'application/octet-stream';

    my $should_convert =
      $convert && ( lc($ext) eq 'csv' || lc($ext) eq 'xls' || lc($ext) eq 'xlsx' );
    my $target_filename = $should_convert ? $file_basename : $filename;

    my $existing_file_id;
    if ($overwrite && $folder_id) {
        # If converting, we look for a file with the base name (which will be a Google Sheet).
        # If not converting, we look for the full filename.
        my $existing_file =
          $self->search_file_by_name_in_folder( $target_filename, $folder_id );
        if ($existing_file) {
            $existing_file_id = $existing_file->{id};
        }
    }

    my $metadata = {};
    my $url;
    my $method;
    my $action;

    if ($existing_file_id) {
        $url    =
          "https://www.googleapis.com/upload/drive/v3/files/$existing_file_id?uploadType=multipart&supportsAllDrives=true";
        $method  = 'PATCH';
        $action  = 'updated';
    } else {
        $url     = 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true';
        $method  = 'POST';
        $action  = 'created';
        $metadata->{name} = $target_filename;
        $metadata->{parents} = [$folder_id] if $folder_id;
        if ($should_convert) {
            $metadata->{mimeType} = 'application/vnd.google-apps.spreadsheet';
        }
    }

    my $boundary = "boundary" . time();
    my $content;
    $content .= "--$boundary\r\n";
    $content .= "Content-Type: application/json; charset=UTF-8\r\n\r\n";
    $content .= $self->{json}->encode($metadata) . "\r\n";
    $content .= "--$boundary\r\n";
    $content .= "Content-Type: $mime_type\r\n\r\n";
    $content .= read_file( $file_path, binmode => ':raw' ) . "\r\n";
    $content .= "--$boundary--\r\n";

    my $req = HTTP::Request->new( $method => $url,
        [ 'Content-Type' => "multipart/related; boundary=$boundary" ],
        $content );

    my $response = $self->_api_request($req);

    my $api_action_verb = $existing_file_id ? 'Update' : 'Upload';
    croak "$api_action_verb failed: " . $response->status_line . "\n" . $response->decoded_content
      unless $response->is_success;

    return ( $self->{json}->decode( $response->decoded_content ), $action );
}

sub get_file_info {
    my ( $self, $file_id, $fields ) = @_;
    $fields //= 'id,name,mimeType,owners,shared,permissions,parents';

    return unless $file_id;

    my $url = "https://www.googleapis.com/drive/v3/files/$file_id?fields=$fields&supportsAllDrives=true";
    warn "DEBUG: get_file_info - Requesting URL: $url\n";
    my $req = HTTP::Request->new( GET => $url );
    my $response = $self->_api_request($req);

    warn "DEBUG: get_file_info - Response status: " . $response->status_line . "\n";
    unless ($response->is_success) {
        warn "DEBUG: get_file_info - Error response body: " . $response->decoded_content . "\n";
        return;
    }
    warn "DEBUG: get_file_info - Success! Response: " . $response->decoded_content . "\n";
    return $self->{json}->decode( $response->decoded_content );
}

sub get_user_info {
    my ($self) = @_;
    my $url = 'https://gmail.googleapis.com/gmail/v1/users/me/profile';
    my $req = HTTP::Request->new( GET => $url );
    my $response = $self->_api_request($req);

    return unless $response->is_success;
    return $self->{json}->decode( $response->decoded_content );
}

sub send_email_via_gmail {

    my ( $self, $recipient, $subject, $body, $sender ) = @_;

    my $message = $sender ? "From: $sender\r\n" : "";
    $message .= "To: $recipient\r\n";
    $message .= "Subject: $subject\r\n";
    $message .= "Content-Type: text/plain; charset=utf-8\r\n\r\n";
    $message .= $body;

    my $encoded_message = encode_base64( $message, '' );
    $encoded_message =~ s/\+/-/g;
    $encoded_message =~ s/\//_/g;
    $encoded_message =~ s/=+$//;

    my $url     = 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send';
    my $content = $self->{json}->encode( { raw => $encoded_message } );
    my $req     = HTTP::Request->new( POST => $url, [ 'Content-Type' => 'application/json' ], $content );

    my $response = $self->_api_request($req);
    return $response;
}


sub test_basic_api_access {
    my ($self) = @_;
    my $url = 'https://www.googleapis.com/drive/v3/about?fields=user,storageQuota';
    my $req = HTTP::Request->new( GET => $url );
    my $response = $self->_api_request($req);
    return $response->is_success ? $self->{json}->decode( $response->decoded_content ) : undef;
}

sub check_oauth_scopes {
    my ($self) = @_;
    $self->get_access_token() unless $self->{access_token};
    my $url = "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=" . $self->{access_token};
    my $req = HTTP::Request->new( GET => $url );
    # This one doesn't need auth header
    my $response = $self->{ua}->request($req);
    return $response->is_success ? $self->{json}->decode( $response->decoded_content ) : undef;
}

sub test_folder_upload_permission {
    my ($self, $folder_id) = @_;
    my $test_metadata = {
        name    => "permission_check_" . time(),
        parents => [$folder_id],
    };
    my $url = 'https://www.googleapis.com/drive/v3/files&supportsAllDrives=true';
    my $req = HTTP::Request->new( POST => $url, 
        ['Content-Type' => 'application/json'], 
        $self->{json}->encode($test_metadata)
    );
    my $response = $self->_api_request($req);

    if ($response->is_success) {
        # Cleanup the test file
        my $data = $self->{json}->decode($response->decoded_content);
        my $del_req = HTTP::Request->new(DELETE => "https://www.googleapis.com/drive/v3/files/$data->{id}&supportsAllDrives=true");
        $self->_api_request($del_req);
        return 1;
    }
    return 0;
}

1;
