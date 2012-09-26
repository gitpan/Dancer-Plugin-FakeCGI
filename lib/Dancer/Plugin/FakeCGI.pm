package Dancer::Plugin::FakeCGI;

use strict;
use warnings;

use Dancer::Plugin;
use Dancer::Config;
use Dancer ':syntax';

use Cwd;
use Carp;
use Test::TinyMocker;
use IO::Capture::Stdout;
use CGI::Compile;

=encoding utf8

=head1 NAME

Dancer::Plugin::FakeCGI - run CGI methods or Perl-files under Dancer

=head1 SYNOPSIS



=head1 DESCRIPTION

Supports to run CGI perl files on CGI methods under Dancer.

=head1 CONFIGURATION

    plugins:
       FakeCGI:
          cgi-dir: 'cgi-bin'
          cgi-package: 'lib/CGI'

C<cgi-dir> - for setting directory where is placed Perl CGI file, standart is 'cgi-bin'

C<cgi-package> - for setting INC library where is CGI packages, standart is nothing.

=head1 TODO

Emulation of this CGI methods: header(), cookie()

=head1 METHODS

=cut

our $VERSION = '0.2';

# Own handles
my $capture        = undef;
my $settings       = undef;
my %handle_require = ();
my %handle_file    = ();
my %handle_mock    = ();

# Must first initialize faked Apache.pm and after that CGI
BEGIN {
    my %old_ENV = %ENV;
    $ENV{MOD_PERL}             = 1;
    $ENV{MOD_PERL_API_VERSION} = 1;

    my ($pack, $filename) = caller;
    my $dir = $filename;
    $dir =~ s/\.pm//;
    unshift(@INC, $dir);

    # Import fake Apache
    require Apache;
    Apache->import;

    # Setting callbacks
    Apache::_set_callback_func('read', \&_apache_read);
    Apache::_set_callback_func('args', \&_apache_args);

    # Import CGI
    require CGI;
    CGI->import('header');

    %ENV = %old_ENV;
    shift(@INC);
}

# Loading setting
sub _load_settings {
	my $first = !defined($settings) ? 1 : 0;
    $settings = plugin_setting() || {};
	unshift(@INC, path(setting('confdir'), $settings->{'cgi-package'})) if ($first && $settings->{'cgi-package'});
}

# Faked method for Apache->read is a built-in function, and so can do magic.
# You can accomplish something similar with your own functions, though, by declaring a function prototype:
sub _apache_read {
	my $buf = \$_[0];
	shift;
    my ($len, $offset) = @_;

	no strict 'refs';
    $$buf = substr(request->body(), $offset, $len);
	return length($$buf);
}

# Faked method for Apache->args
sub _apache_args {
    return "";
    my %all_params = params();
    my @a          = ();
    while (my ($k, $d) = each %all_params) {
        push(@a, $k . "=" . ($d || ""));
    }
    return join("&", @a);
}

#
my $dancer_version = (exists &dancer_version) ? int(dancer_version()) : 1;
my ($logger);
if ($dancer_version == 1) {
    require Dancer::Config;
    Dancer::Config->import();

    #    $logger = sub { Dancer::Logger->can($_[0])->($_[1]) };
} else {

    #    $logger = sub { log @_ };
}

# Method for loading module
sub _load_package {
    my $package = shift;

    my $pack = caller;
    unless (exists($handle_require{$package})) {
        my ($eval_result, $eval_error) = _eval("package $pack;require $package @_;1;");
        croak("Problem with require $package: $eval_error") unless ($eval_result);
        $handle_require{$package} = 1;
		return $eval_result;
    }
	return 1;
}

# Method for compile files
sub _compile_file {
    my $file = shift;

	my $timer = undef;
	if (setting('use_timer')) {
		$timer = Dancer::Timer->new();
	}

    my $sub = undef;
    unless (exists($handle_require{$file})) {
		# Change to current dir where is cgi-bin
		my $currWorkDir = &Cwd::cwd();
		#my $dir = dirname($file);
		my $dir = path(setting('confdir'), ($settings->{'cgi-bin'} || 'cgi-bin'));
		chdir($dir);
        $sub = CGI::Compile->compile($file);
		chdir($currWorkDir);
        $handle_require{$file} = $sub;
    } else {
        $sub = $handle_require{$file};
    }

	debug("Loading $file in " . $timer->to_string . " seconds") if ($timer);
    return $sub;
}

# Eval function
sub _eval {
    my ($code, @args) = @_;

    # Work around oddities surrounding resetting of $@ by immediately
    # storing it.
    my ($sigdie, $eval_result, $eval_error);
    {
        local ($@, $!, $SIG{__DIE__});    # isolate eval
        $eval_result = eval $code;               ## no critic (BuiltinFunctions::ProhibitStringyEval)
        $eval_error  = $@;
        $sigdie      = $SIG{__DIE__} || undef;
    }

    # make sure that $code got a chance to set $SIG{__DIE__}
    $SIG{__DIE__} = $sigdie if defined $sigdie;

    return ($eval_result, $eval_error);
}

# Retype header function
sub _cgi_header {
    my @p = @_;

    shift(@p) if (@p && ref($p[0]));
    my (@header);

    #return "" if $self->{'.header_printed'}++ and $HEADERS_ONCE;

    my ($type, $status, $cookie, $target, $expires, $nph, $charset, $attachment, $p3p, @other) = rearrange([
            ['TYPE', 'CONTENT_TYPE', 'CONTENT-TYPE'],
            'STATUS', ['COOKIE', 'COOKIES'],
            'TARGET', 'EXPIRES', 'NPH', 'CHARSET', 'ATTACHMENT', 'P3P'
        ],
        @p
    );

    #$nph ||= $NPH;

    $type ||= 'text/html' unless defined($type);

    # sets if $charset is given, gets if not
    #$charset = $self->charset( $charset );

    # rearrange() was designed for the HTML portion, so we
    # need to fix it up a little.
    for (@other) {

        # Don't use \s because of perl bug 21951
        next unless my ($header, $value) = /([^ \r\n\t=]+)=\"?(.+?)\"?$/s;

        #($_ = $header) =~ s/^(\w)(.*)/"\u$1\L$2" . ': '.$self->unescapeHTML($value)/e;
    }

    $type .= "; charset=$charset"
      if $type ne ''
          and $type !~ /\bcharset\b/
          and defined $charset
          and $charset ne '';

    # Maybe future compatibility.  Maybe not.
    my $protocol = $ENV{SERVER_PROTOCOL} || 'HTTP/1.0';
    push(@header, $protocol . ' ' . ($status || '200 OK')) if $nph;

    #push(@header,"Server: " . &server_software()) if $nph;

    push(@header, "Status: $status")        if $status;
    push(@header, "Window-Target: $target") if $target;
    if ($p3p) {
        $p3p = join ' ', @$p3p if ref($p3p) eq 'ARRAY';
        push(@header, qq(P3P: policyref="/w3c/p3p.xml", CP="$p3p"));
    }

    # push all the cookies -- there may be several
    if ($cookie) {

        #    my (@cookie) = ref($cookie) && ref($cookie) eq 'ARRAY' ? @{$cookie} : $cookie;
        #    for (@cookie) {
        #        #my $cs = UNIVERSAL::isa($_, 'CGI::Cookie') ? $_->as_string : $_;
        #        push(@header, "Set-Cookie: $cs") if $cs ne '';
        #    }
    }

    # if the user indicates an expiration time, then we need
    # both an Expires and a Date header (so that the browser is
    # uses OUR clock)
    push(@header, "Expires: " . expires($expires, 'http'))
      if $expires;
    push(@header, "Date: " . expires(0, 'http')) if $expires || $cookie || $nph;

    #push(@header, "Pragma: no-cache") if $self->cache();
    push(@header, "Content-Disposition: attachment; filename=\"$attachment\"") if $attachment;
    push(@header, map { ucfirst $_ } @other);
    push(@header, "Content-Type: $type") if $type ne '';
    #my $header = join($CRLF, @header) . "${CRLF}${CRLF}";

    #if (($MOD_PERL >= 1) && !$nph) {
    #    $self->r->send_cgi_header($header);
    #    return '';
    #}
    #return $header;
    #

    # Must be returned one space character !!!
    return " ";
}

# Retype cookie function
sub _cgi_cookie {

}

# what we run on before hook
hook before => sub {
    my $route_handler = shift;
    $capture = IO::Capture::Stdout->new();
};

# what we run on after hook
hook after => sub {
    undef $capture;
};

#
sub _key_fake_cgi_mock {
    return join("::", @_);
}

# Function run before faking
sub _fake_before {
    _load_settings() if (!$settings);

    #mock 'CGI' => method 'header' => \&_cgi_header;
    #mock 'CGI' => method 'header' => should {return " ";};
    my $key = _key_fake_cgi_mock('CGI', 'header');

    fake_cgi_mock({
            package => 'CGI',
            method  => 'header',
            func    => sub { return " "; }
        }) unless (exists($handle_mock{$key}));

    # Mocking header
    while (my ($k, $d) = each %handle_mock) {
        mock($d->{package}, $d->{method}, $d->{func});
    }

    $capture->start();    # STDOUT Output captured

    Dancer::Factory::Hook->instance->execute_hooks('fake_cgi_before', $capture);
}

# Function run after faking
sub _fake_after {
    $capture->stop();     # STDOUT output sent to wherever it was before 'start'

    # Unmocking CGI methods
    #unmock 'CGI' => methods ['header'];
    while (my ($k, $d) = each %handle_mock) {
        unmock($d->{package}, $d->{method});
        delete($handle_mock{$k}) unless ($d->{not_destroy});
    }

    Dancer::Factory::Hook->instance->execute_hooks('fake_cgi_after', $capture);
}

=head2 fake_cgi_mock

Array of Hashref of methods which will be mocked.

=head1 HASHREF of params

=over

=item package => name of package where is method, when not defined, than we use C<CGI>

=item method  => method in specified package which we want to mocked

=item func    => code reference of function which we want to run instead specieified function

=item not_destroy => 1 for not unmocking back after fast_cgi_* function ended.

=back

Standart of method which we automatically mocked is CGI->header.

=cut

register fake_cgi_mock => sub {
    _load_settings() if (!$settings);

    # { package =>, method=>, func=>, not_destroy=>}
    foreach my $rh (@_) {
        next if (!$rh->{func} || ref($rh->{func}) ne "CODE");
        next if (!$rh->{method});    # TODO: test if given method exists in package
        $rh->{package}     ||= "CGI";
        $rh->{not_destroy} ||= 0;
        my $key = _key_fake_cgi_mock($rh->{package}, $rh->{method});
        $handle_mock{$key} = $rh;
		#CGI->import($rh->{method}) if ($rh->{package} eq "CGI");
    }
};

=head2 fake_cgi_method

Method for runned specified CGI method-function and return values of runned function.

=head1 PARAMS

=over

=item Package name where is method, which we run. Automatically load this package to memory in first run.

=item Method name which we run.

=item Arguments for given method 

=back

=cut

register fake_cgi_method => sub {
    my $package = shift;
    my $method  = shift;
    my @args    = @_;

    _load_settings() if (!$settings);

   	return if ($package && !_load_package($package));

    return if (!defined($method));

	unless ($package->can($method)) {
		croak ("Not existed method '$method' in package '$package'");
		return;
	}

    _fake_before($package);

	my $timer = undef;
	if (setting('use_timer')) {
		$timer = Dancer::Timer->new();
	}

    my $ret;
    {
        no strict 'refs';
        $ret = &{(defined($package) ? ($package . "::") : "") . $method}(@args || undef);
    }

	debug("Running method $method in package $package in " . $timer->to_string . " seconds") if ($timer);

    _fake_after();
    return $ret;
};

# Return filename
sub _get_file_name {
	my $name = shift;

    _load_settings() if (!$settings);

    unless (defined($name)) {
        croak("Not defined filename");
		return undef;
	}

	my $dir = path(setting('confdir'), ($settings->{'cgi-bin'} || 'cgi-bin'));
	my $filename = $dir . "/" . $name;
	if (!-s $filename) {
        croak("Can't read file $name in $dir");
		return undef;
	}

	return $filename;
}


=head2 fake_cgi_file

Method for runned specified Perl CGI file and returned exit value

=head1 PARAMS

=over

=item Perl CGI filename and first in first run we compiled this file into memory

=back

=cut

register fake_cgi_file => sub {
    my $file = shift;

	my $fname = _get_file_name($file) || return;
    my $sub = _compile_file($fname);

    _fake_before();

	my $timer = undef;
	if (setting('use_timer')) {
		$timer = Dancer::Timer->new();
	}

    my $ret = &{$sub}() if (ref($sub));
	debug("Running $file in " . $timer->to_string . " seconds") if ($timer);

    _fake_after();

    return $ret;
};

=head2 fake_cgi_as_string

=head1 TYPES

=over

=item Return captured strings from CGI, which will be printed to STDOUT

=item If first arguments is reference to scallar, than captured strings will be added to this reference and returned size of captured string.

=back

=cut

register fake_cgi_as_string => sub {
    if (@_ == 1 && ref($_[0]) eq "SCALAR") {
        my $str = $_[0];
		$$str = "";
        my $len = 0;
        while (my $line = $capture->read) {
            $len += length($line);
            $$str .= $line;
        }
        return $len;
    }

    my $ret = "";
    while (my $line = $capture->read) {
        $ret .= $line;
    }
    return $ret;
};

=head2 fake_cgi_compile

Load packages into memory or Compiled files into memory

=head1 PARAMS is array of HASHREF

=over

=item filename => compile Perl filename into memory

=item package  => load package into memory

=back

=cut

register fake_cgi_compile => sub {
	foreach my $rh (@_)	{
		if (ref($rh) ne "HASH") { 
			croak("Must be hash");
		} elsif (exists($rh->{filename}))	{
			my $fname = _get_file_name($rh->{filename});
            _compile_file($fname) if ($fname);
		} elsif (exists($rh->{package}))	{
            _load_package($rh->{package});
		} else {
			croak("Nothing defined");
		}
	}
};

=head1 HOOKS

This plugin uses Dancer's hooks support to allow you to register code that
should execute at given times.

=head1 TYPES

=over

=item fake_cgi_before : hook which will be called before run CGI method or Perl CGI file

=item fake_cgi_after  : hook which will be called after runned CGI method or Perl CGI file

=back

In both functions was as first arguments reference to C<IO::Capture::Stdout>

=head1 EXAMPLE

    hook 'fake_cgi_before' => sub {
        my $capture = shift;
        # do something with the new DB handle here
    };

=cut

Dancer::Factory::Hook->instance->install_hooks(qw(
      fake_cgi_before
      fake_cgi_after
));

#register_hook(qw());
register_plugin(for_versions => ['1', '2']);

1;    # End of Dancer::Plugin::FakeCGI
__END__

=head1 AUTHOR

Igor Bujna, C<< <igor.bujna@post.cz> >>


=head1 CONTRIBUTING


=head1 ACKNOWLEDGEMENTS


=head1 BUGS


=head1 SUPPORT


=head1 LICENSE AND COPYRIGHT

Copyright 2010-12 Igor Bujna.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=head1 SEE ALSO

L<Dancer>

L<IO::Capture::Stdout>

L<CGI::Compile>

L<Test::TinyMocker>

=cut
