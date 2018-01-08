#!/usr/bin/env perl
#
# Perforce Swarm Trigger Script
#
# @copyright   2015 Perforce Software. All rights reserved.
# @version     <release>/<patch>
#
# This script is used to push Perforce events into Swarm or to restrict committing
# changes that are associated to reviews in Swarm. This script requires certain
# variables defined to operate correctly (described below).
#
# This script should be executed in one of the following ways:
#
#   swarm-trigger.pl -t <type> -v <value> [-p <p4port>] [-r] [-g <group-to-exclude>]
#       [-c <config file>]
#
#   swarm-trigger.pl -o
#
# Swarm trigger is meant to be called from a Perforce trigger. It should be placed
# on the Perforce Server machine. Check the output from 'swarm-trigger.pl -o' for
# an example configuration that can be copied into Perforce triggers.
#
# The -t <type> specifies the Swarm trigger type, one of: job, user, userdel,
# group, groupdel, changesave, shelve, commit, ping, enforce, strict.
#
# The -v <value> specifies the ID value, e.g. Perforce change number for 'commit'
# type, username for 'user' type etc.
#
# The -p <port> specifies the optional (recommended) P4PORT, only intended for
# '-t enforce' or '-t strict'.
#
# The -r will make the Swarm trigger perform checks only on changes that are in
# review (only used with '-t enforce' or '-t strict').
#
# The -g <group> specifies optional group to exclude for '-t strict' or '-t enforce'.
# Members of this group, or subgroups thereof will not be subject to these triggers.
#
# The -c <config_file> specifies optional config file to source variables from
# (see below). Anything defined in the <config_file> will override variables
# defined in the default config files (see below).
#
# The -o will output the sample trigger lines that can be copied into Perforce
# triggers.
#
# You can utilize one of the following default configuration files to define the
# variables needed:
#
#   /etc/perforce/swarm-trigger.conf
#   /opt/perforce/etc/swarm-trigger.conf
#   swarm-trigger.conf (in the same directory as this script)
#
# The following config variables are recognized and utilized by the Swarm trigger
# script:
#
#   SWARM_HOST          hostname of your Swarm instance, with leading http://
#                       or https://
#
#   SWARM_TOKEN         the token used when talking to Swarm to offer some security
#                       to obtain the value, log in to Swarm as a super user and
#                       select 'About Swarm'
#
#   ADMIN_USER          for enforcing reviewed changes, optionally specify the
#                       Perforce user with admin privileges (to read keys);
#                       if not set, will use whatever Perforce user is set in
#                       environment
#
#   ADMIN_TICKET_FILE   for enforcing reviewed changes, optionally specify the
#                       location of the p4tickets file if different from the
#                       default '$HOME/.p4tickets'
#                       ensure this user is a member of a group with an 'unlimited'
#                       or very long timeout; then, manually login as this user
#                       from the Perforce server machine to set the ticket
#
#   P4_PORT             for enforcing reviewed changes, optionally specify the
#                       Perforce port
#                       note that this value will be ignored if the trigger script
#                       is called with '-p'
#
#   P4                  for '-t strict' and '-t enforce', we use the 'p4' utility
#                       if 'p4' isn't available in the PATH of the environment in
#                       which Perforce trigger scripts run, specify the full path
#                       of the utility here (default value 'p4')
#
#   EXEMPT_FILE_COUNT   changes with total number of files equal or greater than
#                       this number (if set to a positive integer) will not be
#                       subject to strict or enforce triggers
#
#   EXEMPT_EXTENSIONS   comma-separated list of file extensions; changes having
#                       only files with these extensions will not be subject to
#                       strict or enforce triggers
#
#   VERIFY_SSL          either 0 or 1, where 1 will validate the SSL certificate
#                       of the Swarm web server, and 0 will skip validation
#                       allowing the use of self-signed certificates.
#
# These config variables can also be specified inside this script itself (under
# the "%config" variable below). Note that for the later option, any values
# defined in the default config files (or one specified via -c) will override
# what is set here. In addition, if you replace or update this script to a new
# version, please ensure you preserve your changes.
#
# Example of configuration file:
#
#   SWARM_HOST="http://my-swarm-host"
#   SWARM_TOKEN="MY-UUID-STYLE-TOKEN"
#   ADMIN_USER=""
#   ADMIN_TICKET_FILE=""
#   P4="p4"
#
# For '-t strict' and '-t enforce', P4 variable must be specified if your 'p4'
# utility is not in the PATH of the environment in which Perforce trigger script
# runs. For other types, SWARM_HOST and SWARM_TOKEN variables must be specified.
#
# Please report any bugs or feature requests to <support@perforce.com>.

# Specify the fallback config values here. Be aware that they will be overridden
# by values of matching variables in default config files or the one specified
# via -c as described above.
my %config = (
    SWARM_HOST        => %SWARMHOST%,
    SWARM_TOKEN       => %SWARMTOKEN%,
    ADMIN_USER        => '',
    ADMIN_TICKET_FILE => '',
    P4_PORT           => '',
    P4                => 'p4',
    EXEMPT_FILE_COUNT => 0,
    EXEMPT_EXTENSIONS => '',
    COOKIES           => '',
    VERIFY_SSL        => 1
);

# DO NOT EDIT PAST THIS LINE ------------------------------------------------ #

require 5.008;

use strict;
use warnings;
use Cwd 'abs_path';
use Digest::MD5;
use File::Basename;
use File::Temp qw(tempfile tempdir mktemp);
use Getopt::Std;
use POSIX qw(SIGINT SIG_BLOCK SIG_UNBLOCK);
use Scalar::Util qw(looks_like_number);
use Sys::Syslog;

sub get_fstat_blocks ($$);
sub fstat_blocks_differ ($$);
sub get_ktext_files_to_fix ($$);
sub get_raw_digest ($$$);
sub escape_shell_arg ($);
sub run;
sub run_quiet;
sub get_trigger_entries;
sub parse_config;
sub get_insensitive_pattern;
sub usage (;$);
sub safe_fork;
sub error ($;$$);

# Introspect a little about ourselves and where we live
my $ME        = basename($0);
my $ABS_ME    = abs_path($0);
my $MY_PATH   = dirname($ABS_ME);
my $IS_WIN    = $^O eq 'MSWin32';
my $HAVE_TINY = eval {
    require HTTP::Tiny;
    import HTTP::Tiny;
    1
};

# Setup logging; syslog won't actually connect till we have something to say
openlog($ME, 'nofatal', 0);

# Show short usage if there are no arguments
usage('short') unless scalar @ARGV;

# Parse out command line arguments
my %args;
error('Unknown or invalid argument provided') and usage('short')
    unless getopts('t:v:p:g:rc:oh', \%args);

# Generate friendlier keys for the commonly used args
@args{qw(type value p4port config_file exclude_group)} = @args{qw(t v p c g)};
$args{review_changes_only} = defined $args{r};

# Show full usage if help is requested
usage() if $args{h};

# Dump just the trigger entries if -o was passed
print get_trigger_entries() and exit 0 if $args{o};

# Looks like we're doing this for real; ensure we have a -t and -v with data.
error('No event type supplied') and usage('short')
    unless defined $args{type} && length $args{type};
error('No ID value supplied') and usage('short')
    unless defined $args{value} && length $args{value};

# Parse any config files
parse_config();

# Strict and enforce triggers happen inline as we need to know the result
if ($args{type} eq 'enforce' || $args{type} eq 'strict') {
    # Sanity test p4 command.
    run($config{P4}, '-V');
    die "$ME: p4 is not set properly; please contact your administrator.\n"
        unless $? == 0;

    # Set up how we call p4.
    my @P4_CMD  = ($config{P4}, "-zprog=p4($ME)");
    my $P4_PORT = defined $args{p4port} ? $args{p4port} : $config{P4_PORT};

    push @P4_CMD, '-p', $P4_PORT
        if length $P4_PORT;
    push @P4_CMD, '-u', $config{ADMIN_USER}
        if length $config{ADMIN_USER};

    $ENV{P4TICKETS} = $config{ADMIN_TICKET_FILE}
        if length $config{ADMIN_TICKET_FILE};

    # Set character-set explicitly if talking to a unicode server.
    if (grep(/\.{3} unicode enabled/, run(@P4_CMD, '-ztag', 'info'))) {
        push @P4_CMD, '-C', 'utf8';
    }

    # Verify our credentials.
    run(@P4_CMD, 'login', '-s');
    if ($? != 0) {
        error(
            "Invalid login credentials to [$P4_PORT] within this trigger script;"
            . ' please contact your administrator.',
            "$args{type}: reject change $args{value}:"
            . " invalid login credentials to [$P4_PORT]"
        );
        exit 1;
    }

    # If we have an exclude group, check if the change user is a member.
    if (defined $args{exclude_group} && length $args{exclude_group}) {
        # Obtain the user from the change.
        my @users = map { m/^\.{3} User (.+)/ ? ($1) : () }
            run(@P4_CMD, '-ztag', 'change', '-o', $args{value});

        # Look for groups the user belongs to and exit if we find a match.
        if (scalar @users and grep { chomp; $_ eq $args{exclude_group} }
            run(@P4_CMD, 'groups', '-i', '-u', $users[0])
        ) {
            syslog(5, "$args{type}: accept change $args{value}: "
                . "'$users[0]' belongs to exempt group '$args{exclude_group}'");
            exit 0;
        }
    }

    # If we are configured with files max limit, check if we are over.
    $config{EXEMPT_FILE_COUNT} = 0 unless looks_like_number($config{EXEMPT_FILE_COUNT});
    if ($config{EXEMPT_FILE_COUNT} > 0) {
        # Get change client (needed for the following fstat command).
        my @client = map { m/^\.{3} Client (.+)/ ? ($1) : () }
            run(@P4_CMD, '-ztag', 'change', '-o', $args{value});

        # Obtain files count in the change.
        my @filesCount = map { m/^\.{3} totalFileCount (\d+)/ ? ($1) : () }
            run(@P4_CMD, '-c', $client[0], 'fstat', '-m1', '-r',
                '-T', 'totalFileCount', '-e', "$args{value}", '-Ro', '//...');

        # If the change has at least exempt-file-count total number of files,
        # log a notice and exit happily.
        if ($filesCount[0] >= $config{EXEMPT_FILE_COUNT}) {
            syslog(5, "$args{type}: accept change $args{value}: "
                . "change has >= $config{EXEMPT_FILE_COUNT} files");
            exit 0;
        }
    }

    # Prepare list of exempt file extensions from the config. The resulting list
    # is either empty or contains trimmed, non-empty extensions with no leading dot.
    my @exemptExtensions = map { s/^\s*\.?|\s+$//g; length $_ ? $_ : () }
        split ',', $config{EXEMPT_EXTENSIONS};

    # If we have exempt extensions, skip the rest if all files in the change have
    # one of the these extensions.
    if (scalar @exemptExtensions) {
        # Get change client (needed for the following fstat command).
        my @client = map { m/^\.{3} Client (.+)/ ? ($1) : () }
            run(@P4_CMD, '-ztag', 'change', '-o', $args{value});

        # Check if change being committed contains a file with extension other
        # than exempt. Note we treat exempt extensions case in-sensitive.
        my @extensionPatterns = get_insensitive_pattern(@exemptExtensions);
        my $pattern = 'depotFile~=\\\\.\\(' . join('\\|', @extensionPatterns) . '\\)\\$';
        my @files   = map { m/^\.{3} depotFile (.+)/ ? ($1) : () }
            run(@P4_CMD, '-c', $client[0], 'fstat', '-m1', '-T', 'depotFile',
                '-F', "^($pattern)", '-e', $args{value}, '-Ro', '//...');

        # Exit happily if change has no other files.
        if (scalar @files == 0) {
            syslog(5, "$args{type}: accept change $args{value}: "
                . 'change contains only files of exempt types ('
                . join(',', @exemptExtensions) . ')');
            exit 0;
        }
    }

    # Search for the review key based on the encoded change number
    (my $changeSearch = $args{value}) =~ s/(.)/3$1/g;
    my $reviewKey = (run(@P4_CMD, 'search', "1301=$changeSearch"))[0];

    # Detect if there is any problem with the command
    if ($? != 0) {
        error(
            "Error searching Perforce for reviews involving this change"
            . "($args{value}); please contact your administrator.",
            "$args{type}: reject change $args{value}: error ($?) from ["
            . join(' ', @P4_CMD) . " search 1301=$changeSearch]"
        );
        exit $?;
    }

    # Detect if no review is found.
    unless (defined $reviewKey) {
        # If enforcement is only set for reviews, exit happy for changes.
        exit 0 if $args{review_changes_only};

        error(
            "Cannot find a Swarm review associated with this change ($args{value}).",
            "$args{type}: reject change $args{value}: no Swarm review found",
            5
        );
        exit 1;
    }

    # Strip the trailing newline from the review key.
    chomp $reviewKey;

    # Detect if the key name is badly formatted.
    if ($reviewKey !~ /swarm\-review\-([0-9a-f]+)/) {
        error(
            "Bad review key for this change ($args{value});"
            . " please contact your administrator.",
            "$args{type}: reject change $args{value}:"
            . " bad Swarm review key ($reviewKey)"
        );
        exit 1;
    }

    # Calculate the human-friendly review ID.
    my $reviewId = hex('ffffffff') - hex($1);

    # Obtain the JSON value of the associated review.
    my $reviewJson = (run(@P4_CMD, 'counter', '-u', $reviewKey))[0];

    # Detect if there is an error or no value for the key (stale index?).
    if ($? != 0 || !defined $reviewJson) {
        error(
            "Cannot find Swarm review data for this change ($args{value}).",
            "$args{type}: reject change $args{value}: empty value for ($reviewKey)",
            4
        );
        exit 1;
    }

    # Locate the change inside the review's associated changes.
    if ($reviewJson !~ m/\"changes\":[^\]]*[^\d]\Q$args{value}\E[^\d]/i) {
        error(
            "This change ($args{value}) is not associated with"
            . " its linked Swarm review $reviewId.",
            "$args{type}: reject change $args{value}:"
            . " change not part of $reviewKey ($reviewId)",
            5
        );
        exit 1;
    }

    # Obtain review state and see if it's 'approved'.
    $reviewJson =~ m/\"state\":\"([^"]*)\"/i;
    if ($1 ne 'approved') {
        error(
            "Swarm review $reviewId for this change ($args{value})"
            . " is not approved ($1).",
            "$args{type}: reject change $args{value}:"
            . " $reviewKey ($reviewId) not approved ($1)",
            5
        );
        exit 1;
    }

    # For -t strict, check that the change's content matches that of its review.
    if ($args{type} eq 'strict') {
        my %reviewFstat = get_fstat_blocks(\@P4_CMD, $reviewId);
        my %changeFstat = get_fstat_blocks(\@P4_CMD, $args{value});

        if (!%reviewFstat || !%changeFstat) {
            error(
                "Error obtaining fstat output for this change ($args{value})"
                . " or its associated review ($reviewId);"
                . " please contact your administrator.",
                "$args{type}: reject change $args{value}: error obtaining"
                . " fstat output for either change or review ($reviewId)"
            );
            exit 1;
        }

        # Before we compare review/change fstat blocks, we fix digests for
        # ktext type files (re-calculate digests with the keywords not
        # expanded), if necessary.
        for my $filespec (get_ktext_files_to_fix(\%reviewFstat, \%changeFstat)) {
            # recalculate digest with keywords not expanded
            $reviewFstat{$filespec}{digest} = get_raw_digest(
                \@P4_CMD, $filespec, $reviewId
            );
            $changeFstat{$filespec}{digest} = get_raw_digest(
                \@P4_CMD, $filespec, $args{value}
            );

            # no need to keep going if the digests of recently updated
            # ktext files don't match.
            last unless $reviewFstat{$filespec}{digest} eq $changeFstat{$filespec}{digest};
        }

        # compare review/change fstat data.
        if (fstat_blocks_differ(\%reviewFstat, \%changeFstat)) {
            error(
                "The content of this change ($args{value}) does not match the"
                . " content of the associated Swarm review ($reviewId).",
                "$args{type}: reject change $args{value}:"
                . " content does not match review ($reviewId)",
                5
            );
            exit 1;
        }
    }

    # Return success at this point.
    exit 0;
}

# Sanity check global variables we need for posting events to Swarm.
if (!length $config{SWARM_HOST} || $config{SWARM_HOST} eq 'http://my-swarm-host') {
    error(
        "SWARM_HOST is not set properly; please contact your administrator.",
        "$args{type}: SWARM_HOST empty or default"
    );
    exit 1;
}
if (!length $config{SWARM_TOKEN} || $config{SWARM_TOKEN} eq 'MY-UUID-STYLE-TOKEN') {
    error(
        "SWARM_TOKEN is not set properly; please contact your administrator.",
        "$args{type}: SWARM_TOKEN empty or default"
    );
    exit 1;
}

# Ping trigger deals with archive files whose content is sent/received via STDIN/STDOUT.
# Although we don't care about the content (it doesn't change), we should read STDIN
# for write operations and print to STDOUT for read operations to avoid potential errors.
if ($args{type} eq 'ping') {
    my @tmp = <STDIN>
        if $args{value} eq 'write';

    print STDOUT "Placeholder file for testing Swarm triggers. Do not modify the content of this file."
        if $args{value} eq 'read';
}

# For other Swarm trigger types, post the event to Swarm asynchronously (detach to the background).
# Note we don't presently background on Windows; only *nix systems.
if (!$IS_WIN) {
    # Flush output immediately; no buffering.
    local $| = 1;

    # Safely fork the process - returns child pid to the parent process and 0
    # to the child process.
    my $pid;
    eval { $pid = safe_fork(); };
    error("Failed to fork: $@") and exit 1 if $@;

    # Exit parent.
    exit 0 if $pid;

    # Close STDOUT and STDERR to allow detaching.
    if ($args{type} ne "ping") {
        close STDOUT;
        close STDERR;
    }
}

# The host really really aught to lead with http already, but add it if needed.
$config{SWARM_HOST} = 'http://' . $config{SWARM_HOST}
    if $config{SWARM_HOST} !~ /^http/;
    
# We assume SWARM_HOST and SWARM_TOKEN are properly set at this point.
my $SWARM_QUEUE = "$config{SWARM_HOST}/queue/add/$config{SWARM_TOKEN}";

# Swarm accepts the POST data in a non-standard format, with both values in a list.
my $options = { content => "$args{type},$args{value}" };

# We only expect to be setting Cookies in a test environment.
if (exists $config{COOKIES} && $config{COOKIES} ne '') {
    $options->{headers} = { 
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Cookie' => $config{COOKIES}
    };
} else {
    $options->{headers} = { 
        'Content-Type' => 'application/x-www-form-urlencoded'
    };
}

# Force verification of SSL certificates if VERIFY_SSL is set.
# HTTP::Tiny does not do this by default.
my %attributes;
if ($config{VERIFY_SSL} == 1) {
    $attributes{'verify_SSL'} = 1;
}

my $failure = "";
if ($HAVE_TINY) {
    my $response = HTTP::Tiny->new(%attributes)->post($SWARM_QUEUE, $options);
    if ($response->{status} == 599 && $config{VERIFY_SSL} == 1) {
        $failure = "Error: ($response->{status}/$response->{reason}) (probably invalid SSL certificate) trying to post [$args{type},$args{value}] to [$SWARM_QUEUE]";
    } elsif ($response->{status} != 200) {
        $failure = "Error: ($response->{status}/$response->{reason}) trying to post [$args{type},$args{value}] to [$SWARM_QUEUE]";
    } elsif ($response->{content} ne "") {
        # It's possible to get a 200 back if we're talking to the wrong web server. We expect
        # no content to be returned by the call to Swarm, so if we get a 200, but also get
        # content returned (such as "It Works!"), then probably something is wrong.
        $failure = "Error: Unexpected content returned by [$SWARM_QUEUE], is this a Swarm server? ($response->{content})";
    }
} else {
    # The tiny module is not available, so use curl
    my @curl_cmd=qw(curl --max-time 10 -sS);
    # Disable verification of certificates
    if($config{VERIFY_SSL} != 1){
         push(@curl_cmd,"--insecure");
    }
    if($config{COOKIES}){
        push(@curl_cmd, "--cookie");
        push(@curl_cmd, $config{COOKIES});
    }
    push(@curl_cmd, "--data",);
    my $output = run(
        @curl_cmd,
        "$args{type},$args{value}",
        $SWARM_QUEUE
    );
    if ($? != 0) {
        $failure = "Error: ($?) trying to post [$args{type},$args{value}] via [curl] to [$SWARM_QUEUE]";
    } elsif ($output) {
        $failure = "Error: Unexpected output from swarm trigger via [curl] to [$SWARM_QUEUE]. [$output]";
    }
}

# Always return success to avoid affecting Perforce users, unless this was a ping command.
if ($failure) {
    syslog(3, $failure);
    if ($args{type} eq "ping") {
        printf("$failure\n");
        exit 1;
    }
}
exit 0;

#==============================================================================
# Local Functions
#==============================================================================

# Returns a hash with fstat data for a given change.
# Hash will contain filespec for each file in the fstat output in key and
# filespec, type and digest in values.
sub get_fstat_blocks ($$) {
    my ($cmd, $change) = @_;

    die 'First argument to '. (caller(0))[3] ." must be an array reference\n"
        unless ref $cmd eq 'ARRAY';

    # Run fstat command to collect data.
    my @fstat = run(
        @$cmd, 'fstat', '-Ol', '-T', 'depotFile,headType,digest', "@=$change"
    );

    # Early exit with an empty block if command failed.
    return {} if $? != 0;

    # Group fstat output by depotFile into blocks.
    my $file;
    my %blocks;
    for (@fstat) {
        if (m/^\.\.\. depotFile (.+)/) {
            $file = $1;
        }

        m/^\.\.\. ([^ ]+) (.+)/;
        $blocks{$file}{$1} = $2 if $file;
    }

    return %blocks;
}

# Compares two fstat blocks and return 1 if they differ or 0 otherwise.
# Fstat blocks do not differ if they have same amount of blocks (files) and
# depotFile, headType and digest data match for each block representing the
# same file.
sub fstat_blocks_differ ($$) {
    my ($a, $b) = @_;

    die 'First argument to '. (caller(0))[3] ." must be a hash reference\n"
        unless ref $a eq 'HASH';
    die 'Second argument to '. (caller(0))[3] ." must be a hash reference\n"
        unless ref $b eq 'HASH';

    # Blocks differ if they have different number of keys.
    return 1 unless keys %{$a} == keys %{$b};

    # We go through blocks in $a and will try to find matching data in $b.
    for my $file (keys %{$a}) {
        # Early exit if key is not present in block $b.
        return 1 unless defined $b->{$file};

        # Compare the values for 'depotFile', 'headType' and 'digest'.
        for my $field ('depotFile', 'headType', 'digest') {
            if (defined $a->{$file}->{$field} && defined $b->{$file}->{$field}) {
                return 1 unless $a->{$file}->{$field} eq $b->{$file}->{$field};
            }
        }
    }

    return 0;
}

# Returns a list with ktext files present in passed fstat blocks whose
# digests should be recalculated (with keywords not expanded) before these
# blocks get compared via fstat_blocks_differ() since in this script we
# consider two ktext files different only when they differ in 'raw' state
# (keywords not expanded).
#
# Since calculating digests can be expensive, we want to do it only if
# necessary, i.e. only if other pieces in fstat blocks are same (number of
# files, file types and digests except for ktext files).
sub get_ktext_files_to_fix ($$) {
    my ($reviewFstat, $changeFstat) = @_;

    die 'First argument to '. (caller(0))[3] ." must be a hash reference\n"
        unless ref $reviewFstat eq 'HASH';
    die 'Second argument passed to '. (caller(0))[3] ." must be a hash reference\n"
        unless ref $changeFstat eq 'HASH';

    # No need to explore more if blocks have different number of keys.
    return () unless scalar keys %{$reviewFstat} == scalar keys %{$changeFstat};

    # We go through review blocks and will try to find matching data in
    # change blocks.
    my @filesToFix;
    for my $filespec (keys %{$reviewFstat}) {
        # No need to fix if review file is not present in change.
        return () unless exists $changeFstat->{$filespec};

        # No need to fix if file types differ.
        return () unless $reviewFstat->{$filespec}->{headType} eq $changeFstat->{$filespec}->{headType};

        # No need to fix if digests for non-ktext files differ.
        my $isKtext = $reviewFstat->{$filespec}->{headType} =~ m/kx?text|.+\+.*k/i;
        my $digestsMatch = $reviewFstat->{$filespec}->{digest} eq $changeFstat->{$filespec}->{digest};
        return () unless ($isKtext || $digestsMatch);

        push @filesToFix, $filespec if $isKtext;
    }

    # Making it this far means that both review and change fstat blocks
    # have same files with same types and all non-ktext file digests match.
    # Return list of ktext files we encountered (they are present in both
    # change/review blocks).
    return @filesToFix;
}

# Returns digest of a given file with keywords not expanded.
sub get_raw_digest ($$$) {
    my ($cmd, $filespec, $change) = @_;

    die 'First argument to '. (caller(0))[3] ." must be an array reference\n"
        unless ref $cmd eq 'ARRAY';

    my $dir      = tempdir(CLEANUP => 1);
    my $filename = mktemp( $dir . '/XXXXXX' );

    # Temporarily capture STDERR in a variable.
    open OLDERR, ">&STDERR";
    local (*RH, *WH);
    pipe RH, WH;
    open STDERR, ">&WH" or die "Cannot open STDERR: $!";
    print OLDERR '';  # to avoid error about OLDERR not being used

    # Run the command to save file with keywords not expanded in temporary
    # location. This will produce an error on old servers (<2012.2) as
    # '-k' option is not available.
    run(@$cmd, 'print', '-k', '-o', $filename, "$filespec@=$change");

    # Read 2 lines of error output from the previous command. If there were
    # no errors, this would wait indefinitely. To avoid it, we artifically
    # produce 2 blank lines of error (doesn't have impact on behaviour).
    print STDERR "\n\n";
    close WH;
    my $error = <RH> . <RH>;
    close RH;

    # Restore STDERR.
    open STDERR, ">&", OLDERR or die "Cannot restore STDERR: $!";

    # Check if the the command failed due to 'Invalid option: -k'.
    if ($? != 0) {
        die "Cannot print into file: $filename [$?]"
            unless $error =~ m/Invalid option\: \-k/i;

        # Try to replace keywords manually.
        my $tmpFile = mktemp( $dir . '/XXXXXX' );
        run(@$cmd, 'print', '-o', $tmpFile, "$filespec@=$change");

        open(my $in,  '<', $tmpFile);
        open(my $out, '>', $filename);
        while (my $line = <$in>) {
            $line =~ s/\$(Id|Header|Date|DateTime|Change|File|Revision|Author)\:[^\$]+\$/\$$1\$/g;
            print $out $line;
        }
        close $in;
        close $out;
    }

    open my $in, '<', $filename;
    return Digest::MD5->new->addfile($in)->hexdigest;
}

# Escapes a string to be used as a shell argument.
sub escape_shell_arg ($) {
    my ($arg) = @_;

    if ($IS_WIN) {
        $arg =~ s/["%!]/ /;
    } else {
        $arg =~ s/\'/\'\\\'/;
    }

    # under Windows, if arg ends with odd number of slashes, add one more
    $arg =~ m/(\\*)$/;
    if ($IS_WIN && length($1) % 2) {
        $arg .= '\\';
    }

    # wrap argument in quotes
    $arg = $IS_WIN
        ? '"'  . $arg . '"'
        : '\''  .$arg . '\'';

    return $arg;
}

# Runs the command specified in parameters and returns the array with lines
# of command output.
sub run {
    my $cmd = join q{ }, map { escape_shell_arg($_) } @_;
    return `$cmd`;
}

sub run_quiet {
    my $cmd = join q{ }, map { escape_shell_arg($_) } @_;
    return $IS_WIN ? `$cmd 1> NUL 2> NUL` : `$cmd &>/dev/null`;
}

# Parses the config files in fixed locations (if they exist) and saves the
# values into %config hash.
sub parse_config {
    my @candidates = (
        !$IS_WIN ? '/etc/perforce/swarm-trigger.conf' : '',
        !$IS_WIN ? '/opt/perforce/etc/swarm-trigger.conf' : '',
        "$MY_PATH/swarm-trigger.conf",
        $args{config_file}
    );

    foreach my $file (@candidates) {
        if (defined $file && length $file && -e $file && open(my $fh, '<', "$file")) {
            while (my $line = <$fh>) {
                chomp $line;
                $line =~ s/#.*$//;
                next unless $line =~ /=/;
                $line =~ s/^\s+|\s+$//g;

                my ($key, $value) = split(/=/, $line, 2);
                $key   =~ s/^['"]?|['"]?\s*$//g; # trim key's whitespace/quotes
                $value =~ s/^\s*['"]?|['"]?$//g; # ditto for the value
                $config{$key} = $value if length $value;
            }
        }
    }
}

# Turn input string(s) into regex patterns for case-insensitive look up.
# Example: 'String' will be turned into '[sS][tT][rR][iI][nN][gG]'.
sub get_insensitive_pattern {
    my @patterns = ();
    for my $string (@_) {
        my @pattern = map { '\\[\\\\' . (lc $_) . '\\\\' . (uc $_) . '\\]' }
            split("", $string);

        push @patterns, join('', @pattern);
    }

    return @patterns;
}

# Returns string with formatted trigger lines that can be copied into
# Perforce triggers.
sub get_trigger_entries {
    my $script = $IS_WIN
        ? "%quote%$^X%quote% %quote%$ABS_ME%quote%"
        : "%quote%$ABS_ME%quote%";

    my $config = $args{config_file}
        ? ' -c %quote%'. abs_path($args{config_file}) .'%quote%'
        : '';

    # Define the trigger entries suitable for this script; replace depot
    # paths as appropriate.
    return <<EOT;
	swarm.job        form-commit   job    "$script$config -t job          -v %formname%"
	swarm.user       form-commit   user   "$script$config -t user         -v %formname%"
	swarm.userdel    form-delete   user   "$script$config -t userdel      -v %formname%"
	swarm.group      form-commit   group  "$script$config -t group        -v %formname%"
	swarm.groupdel   form-delete   group  "$script$config -t groupdel     -v %formname%"
	swarm.changesave form-save     change "$script$config -t changesave   -v %formname%"
	swarm.shelve     shelve-commit //...  "$script$config -t shelve       -v %change%"
	swarm.commit     change-commit //...  "$script$config -t commit       -v %change%"
	#swarm.enforce.1 change-submit  //DEPOT_PATH1/... "$script$config -t enforce -v %change% -p %serverport%"
	#swarm.enforce.2 change-submit  //DEPOT_PATH2/... "$script$config -t enforce -v %change% -p %serverport%"
	#swarm.strict.1  change-content //DEPOT_PATH1/... "$script$config -t strict -v %change% -p %serverport%"
	#swarm.strict.2  change-content //DEPOT_PATH2/... "$script$config -t strict -v %change% -p %serverport%"
EOT
}

# Getopts calls this for --help, we redirect to our usage info.
sub HELP_MESSAGE {
    usage();
}

# Prints usage of this script in standard output.
# If optional parameter is passed with false value, it also prints
# additional messages to STDERR.
sub usage (;$) {
    my ($short) = @_;

    print STDERR <<EOU;
Usage: $ME -t <type> -v <value> \\
         [-p <p4port>] [-r] [-g <group-to-exclude>] [-c <config file>]
       $ME -o
    -t: specify the Swarm trigger type (e.g. job, shelve, commit)
    -v: specify the ID value
    -p: specify optional (recommended) P4PORT, only intended for
        '-t enforce' or '-t strict'
    -r: when using '-t strict' or '-t enforce', only apply this check
        to changes that are in review.
    -g: specify optional group to exclude for '-t enforce' or
        '-t strict'; members of this group, or subgroups thereof will
        not be subject to these triggers
    -c: specify optional config file to source variables
    -o: convenience flag to output the trigger lines

EOU

    exit 99 if $short;

    print STDERR <<EOU;
This script is meant to be called from a Perforce trigger. It should be placed
on the Perforce Server machine and the following entries should be added using
'p4 triggers' (use the -o flag to this script to only output these lines):

EOU

    print STDERR get_trigger_entries();

    print STDERR <<EON;
Notes:

* The use of '%quote%' is not supported on 2010.2 servers (they are harmless
  though); if you're using this version, ensure you don't have any spaces in the
  pathname to this script.

* This script requires configuration to be set in an external configuration file
  or directly in the script itself, such as the Swarm host and token.
  By default, this script will source any of these config file:
    /etc/perforce/swarm-trigger.conf
    /opt/perforce/etc/swarm-trigger.conf
    swarm-trigger.conf (in the same directory as this script)
  Lastly, if -c <config file> is passed, that file will be sourced too.

* For 'enforce' triggers (enforce that a change to be submitted is tied to an
  approved review), or 'strict' triggers (verify that the content of a change to
  be submitted matches the content of its associated approved review), uncomment
  the appropriate lines and replace DEPOT_PATH as appropriate. For additional
  paths to check, increment the trigger name suffix so that each trigger name is
  named uniquely.

* For 'enforce' or 'strict' triggers, you can optionally specify a group whose
  members will not be subject to these triggers.

* For 'enforce' or 'strict' triggers, if your Perforce Server is SSL-enabled,
  add the \"ssl:\" protocol prefix to \"%serverport%\".

EON

    exit 99;
}

# Forks the process safely with protection against interrupts while forking.
# Code borrowed from Net::Server::Daemonize.
sub safe_fork {
    # block signal for fork.
    my $sigset = POSIX::SigSet->new(SIGINT);
    POSIX::sigprocmask(SIG_BLOCK, $sigset)
        or die "Can't block SIGINT for fork: [$!]";

    my $pid = fork();
    die "Couldn't fork: [$!]" unless defined $pid;

    $SIG{'INT'} = 'DEFAULT'; # make SIGINT kill us as it did before.

    POSIX::sigprocmask(SIG_UNBLOCK, $sigset)
        or die "Can't unblock SIGINT for fork: [$!]";

    return $pid;
}

# Helper subroutine to log and print a given message into standard error:
# Parameter 1 is the print message (required)
# Parameter 2 is the log message   (optional), when missing, = param 1
# Parameter 3 is the log priority  (optional), defaults to 3 (error)
sub error ($;$$) {
    # Check the input and provide default values for optional parameters.
    my $printError = $_[0];
    my $logError   = defined $_[1] ? $_[1] : $printError;
    my $logLevel   = defined $_[2] ? $_[2] : 3;

    syslog($logLevel, $logError);
    print STDERR "$printError\n";
}

__END__

=head1 NAME

Perforce Swarm Trigger Script - script for Perforce triggers

=head1 DESCRIPTION

This script is used to push Perforce events into Swarm or to restrict committing
changes that are associated to reviews in Swarm. For full details, please read
the comments in the script file.

=cut
