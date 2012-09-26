package Apache;

use strict;
use warnings;

use vars qw{$AUTOLOAD};

our $VERSION = "0.2";

=head1 NAME

Dancer::Plugin::FakeCGI::Apache - emulation Apache.pm module

=head1 DESCRIPTION

Settings callback for emulation Apache.pm from mod_perl version 1.

=head1 SYNOPSIS

    # Import fake Apache
    require Apache;
    Apache->import;
    
    # Setting callbacks
    Apache::_set_callback_func('read', \&_apache_read);
    Apache::_set_callback_func('args', \&_apache_args);
    

=head1 METHODS


=head2 _set_callback_func

Set callback function for specified called method from mod_perl::Apache.pm

=head1 PARAMS 2

=over 

=item Name of called method

=item Callback function

=over

=item 1. How to call other method see in mod_perl/Apache.pm manual

=item 2. For C<read> function called callback function in this examples:

	$string = $callback_func{'read'}($len, $offset);

=back

=back

=cut

my %callback_func = ();

# Function for setting callback
sub _set_callback_func {
	my ($name, $fn) = @_;
	$callback_func{$name} = $fn;
}

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}
 
sub AUTOLOAD {
	my $self = shift;

	my $name = $AUTOLOAD;
	$name =~ s/.*://;   # strip fully-qualified portion

	return new Apache() if ($name eq 'request');
	return unless(exists($callback_func{$name}));

	my $rh_f = $callback_func{$name};
	{
        no strict 'refs';
		return &$rh_f(@_);
	}
}

# Read function. Callback must returned given string
sub read() {
    my $self = shift;
    my $buf = \$_[0];	# Must be setted as scalarref
	shift;
	my ($len, $offset) = @_;


	return unless(exists($callback_func{'read'}));

    no strict 'refs';
	return $callback_func{'read'}($$buf, $len, $offset);
}

DESTROY {}

=head1 AUTHOR

Igor Bujna C<igor.bujna@post.cz>

=head1 ACKNOWLEDGEMENTS

See L<Dancer::Plugin::FakeCGI/ACKNOWLEDGEMENTS>

=head1 SEE ALSO

L<Dancer::Plugin::FakeCGI>

=cut

1;
__END__

